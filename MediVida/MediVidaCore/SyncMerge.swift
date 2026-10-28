import Foundation

/// Combina datos locales y remotos conservando los cambios pendientes.
public enum SyncMerge {

    /// Combina registros por ID.
    ///
    /// Los registros pendientes conservan la versión local.
    /// Los registros locales ausentes en la nube se ponen en cola.
    /// Si un registro ya archivado coincide exactamente en ambos lados,
    /// se retira de la cola para evitar intentar modificarlo otra vez.
    public static func records(
        local: [HealthRecord],
        remote: [HealthRecord],
        pendingIDs: [String]
    ) -> (items: [HealthRecord], pendingIDs: [String]) {
        var merged = remote
        var queue = pendingIDs

        for localRecord in local {
            if queue.contains(localRecord.id) {
                if let index = merged.firstIndex(
                    where: { $0.id == localRecord.id }
                ) {
                    let remoteRecord = merged[index]

                    // Firestore no permite modificar un registro que ya
                    // está archivado. La versión remota es definitiva:
                    // conservarla y quitar el elemento de la cola evita
                    // reintentos que las reglas siempre rechazarían.
                    if remoteRecord.archived {
                        queue.removeAll { $0 == localRecord.id }
                        continue
                    }

                    merged[index] = localRecord
                } else {
                    merged.append(localRecord)
                }
            } else if !merged.contains(
                where: { $0.id == localRecord.id }
            ) {
                merged.append(localRecord)

                if !queue.contains(localRecord.id) {
                    queue.append(localRecord.id)
                }
            }
        }

        return (items: merged, pendingIDs: queue)
    }

    /// Combina tomas y omisiones usando su ID determinista.
    ///
    /// Si el evento ya existe en la nube, la copia remota se conserva
    /// y se retira de la cola pendiente.
    /// Si un evento local aún no existe remotamente, se conserva y
    /// se pone en cola para sincronizarlo.
    public static func completions(
        local: [DoseCompletion],
        remote: [DoseCompletion],
        pendingIDs: [String]
    ) -> (items: [DoseCompletion], pendingIDs: [String]) {
        let remoteIDs = Set(remote.map(\.id))
        var merged = remote
        var queue = pendingIDs

        for localCompletion in local {
            if queue.contains(localCompletion.id) {
                if remoteIDs.contains(localCompletion.id) {
                    queue.removeAll { $0 == localCompletion.id }
                    continue
                }

                if !merged.contains(
                    where: { $0.id == localCompletion.id }
                ) {
                    merged.append(localCompletion)
                }
            } else if !merged.contains(
                where: { $0.id == localCompletion.id }
            ) {
                merged.append(localCompletion)

                if !queue.contains(localCompletion.id) {
                    queue.append(localCompletion.id)
                }
            }
        }

        return (items: merged, pendingIDs: queue)
    }
}
