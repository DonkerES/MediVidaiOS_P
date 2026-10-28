import Foundation

/// Estado intercambiado entre la aplicación y el proceso de sincronización.
public struct MediVidaSyncSnapshot {
    public var records: [HealthRecord]
    public var completions: [DoseCompletion]
    public var profile: PatientProfile
    public var queue: SyncQueueState

    public init(
        records: [HealthRecord],
        completions: [DoseCompletion],
        profile: PatientProfile,
        queue: SyncQueueState
    ) {
        self.records = records
        self.completions = completions
        self.profile = profile
        self.queue = queue
    }
}

/// Coordina la descarga, combinación, persistencia y escritura
/// de los cambios pendientes. Utiliza el mismo repositorio que la app.
@MainActor
public enum MediVidaSyncCoordinator {

    public static func synchronize(
        repository: any MediVidaSyncRepository,
        getSnapshot: @escaping @MainActor () -> MediVidaSyncSnapshot,
        applySnapshot: @escaping @MainActor (MediVidaSyncSnapshot) -> Void,
        persist: @escaping @MainActor () throws -> Void
    ) async -> String {

        let remoteRecords: [HealthRecord]
        let remoteCompletions: [DoseCompletion]
        let remoteProfile: PatientProfile?

        // Descargar los datos antes de modificar el estado local.
        do {
            remoteRecords = try await repository.fetchRecords()
            remoteCompletions = try await repository.fetchCompletions()
            remoteProfile = try await repository.fetchProfile()
        } catch {
            return "No se completó la sincronización. "
                + "Se conservan los cambios locales: "
                + error.localizedDescription
        }

        var problems: [String] = []

        // Volver a leer el estado después de la descarga para no
        // trabajar con una copia local anterior a la operación.
        var state = getSnapshot()

        let recordMerge = SyncMerge.records(
            local: state.records,
            remote: remoteRecords,
            pendingIDs: state.queue.pendingRecordIDs
        )

        state.records = recordMerge.items
        state.queue.pendingRecordIDs = recordMerge.pendingIDs

        let completionMerge = SyncMerge.completions(
            local: state.completions,
            remote: remoteCompletions,
            pendingIDs: state.queue.pendingCompletionIDs
        )

        state.completions = completionMerge.items
        state.queue.pendingCompletionIDs = completionMerge.pendingIDs

        if !state.queue.profilePending {
            if let remoteProfile {
                state.profile = remoteProfile
            } else {
                let cleanName = state.profile.name.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if (2...100).contains(cleanName.count) {
                    state.queue.markProfilePending()
                }
            }
        }

        // Primero conservar localmente la combinación y sus colas.
        applySnapshot(state)

        do {
            try persist()
        } catch {
            return "No se completó la sincronización. "
                + "Se conservan los cambios locales: "
                + error.localizedDescription
        }

        // Enviar los registros pendientes.
        for recordID in getSnapshot().queue.pendingRecordIDs {
            let beforeWrite = getSnapshot()

            guard let record = beforeWrite.records.first(
                where: { $0.id == recordID }
            ) else {
                var updated = getSnapshot()
                updated.queue.pendingRecordIDs.removeAll {
                    $0 == recordID
                }
                applySnapshot(updated)

                do {
                    try persist()
                } catch {
                    var restored = getSnapshot()
                    restored.queue.enqueueRecord(recordID)
                    applySnapshot(restored)

                    problems.append(
                        "No se pudo actualizar la cola local: "
                        + error.localizedDescription
                    )
                }

                continue
            }

            let attempt = await SyncRetryProcessor.record(
                id: recordID,
                queue: beforeWrite.queue,
                write: {
                    try await repository.saveRecord(record)
                },
                snapshotIsCurrent: {
                    getSnapshot().records.first(
                        where: { $0.id == recordID }
                    ) == record
                }
            )

            if let message = attempt.errorMessage {
                problems.append("Registro \(record.title): " + message)
                continue
            }

            guard attempt.acknowledged else {
                continue
            }

            // Actualizar la cola vigente, no la copia anterior a la
            // escritura. Así no se descartan otros cambios encolados.
            var updated = getSnapshot()

            guard updated.queue.acknowledgeRecord(
                recordID,
                writeSucceeded: true,
                snapshotIsCurrent: updated.records.first(
                    where: { $0.id == recordID }
                ) == record
            ) else {
                continue
            }

            applySnapshot(updated)

            do {
                try persist()
            } catch {
                var restored = getSnapshot()
                restored.queue.enqueueRecord(recordID)
                applySnapshot(restored)

                problems.append(
                    "No se pudo guardar la cola del registro: "
                    + error.localizedDescription
                )
            }
        }

        // Enviar el perfil pendiente.
        if getSnapshot().queue.profilePending {
            let profileToSave = getSnapshot().profile

            let attempt = await SyncRetryProcessor.profile(
                queue: getSnapshot().queue,
                write: {
                    try await repository.saveProfile(profileToSave)
                },
                snapshotIsCurrent: {
                    Self.sameProfile(getSnapshot().profile, profileToSave)
                }
            )

            if let message = attempt.errorMessage {
                problems.append("Perfil: " + message)
            } else if attempt.acknowledged {
                var updated = getSnapshot()

                let acknowledged = updated.queue.acknowledgeProfile(
                    writeSucceeded: true,
                    snapshotIsCurrent: Self.sameProfile(
                        updated.profile,
                        profileToSave
                    )
                )

                if acknowledged {
                    applySnapshot(updated)

                    do {
                        try persist()
                    } catch {
                        var restored = getSnapshot()
                        restored.queue.markProfilePending()
                        applySnapshot(restored)

                        problems.append(
                            "No se pudo guardar la cola del perfil: "
                            + error.localizedDescription
                        )
                    }
                }
            }
        }

        // Enviar las tomas y omisiones al final.
        for completionID in getSnapshot().queue.pendingCompletionIDs {
            let beforeWrite = getSnapshot()

            guard let completion = beforeWrite.completions.first(
                where: { $0.id == completionID }
            ) else {
                var updated = getSnapshot()
                updated.queue.pendingCompletionIDs.removeAll {
                    $0 == completionID
                }
                applySnapshot(updated)

                do {
                    try persist()
                } catch {
                    var restored = getSnapshot()
                    restored.queue.enqueueCompletion(completionID)
                    applySnapshot(restored)

                    problems.append(
                        "No se pudo actualizar la cola de tomas: "
                        + error.localizedDescription
                    )
                }

                continue
            }

            guard let record = getSnapshot().records.first(
                where: { $0.id == completion.recordID }
            ) else {
                problems.append(
                    "No se sincronizó una toma porque falta su registro."
                )
                continue
            }

            guard !record.archived else {
                problems.append(
                    "Una toma sigue pendiente porque el registro está archivado."
                )
                continue
            }

            let attempt = await SyncRetryProcessor.completion(
                id: completionID,
                queue: beforeWrite.queue,
                write: {
                    try await repository.saveCompletion(
                        completion,
                        updatedRecord: nil
                    )
                },
                snapshotIsCurrent: {
                    getSnapshot().completions.first(
                        where: { $0.id == completionID }
                    ) == completion
                }
            )

            if let message = attempt.errorMessage {
                problems.append("Historial de dosis: " + message)
                continue
            }

            guard attempt.acknowledged else {
                continue
            }

            var updated = getSnapshot()

            guard updated.queue.acknowledgeCompletion(
                completionID,
                writeSucceeded: true,
                snapshotIsCurrent: updated.completions.first(
                    where: { $0.id == completionID }
                ) == completion
            ) else {
                continue
            }

            applySnapshot(updated)

            do {
                try persist()
            } catch {
                var restored = getSnapshot()
                restored.queue.enqueueCompletion(completionID)
                applySnapshot(restored)

                problems.append(
                    "No se pudo guardar la cola de tomas: "
                    + error.localizedDescription
                )
            }
        }

        let finalState = getSnapshot()

        if let firstProblem = problems.first {
            return "Sincronización parcial: " + firstProblem
        }

        if finalState.queue.pendingRecordIDs.isEmpty
            && finalState.queue.pendingCompletionIDs.isEmpty
            && !finalState.queue.profilePending {
            return "Sincronizado con Firebase"
        }

        return "Quedan cambios pendientes de sincronización."
    }

    private static func sameProfile(
        _ first: PatientProfile,
        _ second: PatientProfile
    ) -> Bool {
        first.name == second.name
            && first.age == second.age
            && first.weight == second.weight
            && first.blood == second.blood
            && first.allergies == second.allergies
            && first.contact == second.contact
            && first.phone == second.phone
            && first.notifications == second.notifications
    }
}
