import Foundation
import FirebaseFirestore

@MainActor
final class MediVidaFirestoreRepository: MediVidaSyncRepository {

    private let database = Firestore.firestore()
    private let userID: String

    private var userDocument: DocumentReference {
        database.collection("users").document(userID)
    }

    private var recordsCollection: CollectionReference {
        userDocument.collection("records")
    }

    private var completionsCollection: CollectionReference {
        userDocument.collection("completions")
    }

    init(userID: String) {
        self.userID = userID
    }

    // MARK: - Conversión de tipos

    private func firestoreKind(_ kind: RecordKind) -> String {
        switch kind {
        case .medicine: return "MEDICINE"
        case .appointment: return "APPOINTMENT"
        case .meal: return "MEAL"
        case .restriction: return "RESTRICTION"
        }
    }

    private func recordKind(_ value: String) -> RecordKind? {
        switch value {
        case "MEDICINE": return .medicine
        case "APPOINTMENT": return .appointment
        case "MEAL": return .meal
        case "RESTRICTION": return .restriction
        default: return nil
        }
    }

    // MARK: - Registros

    private func encodeRecord(_ record: HealthRecord) -> [String: Any] {
        let stockRemaining: Any =
            record.stockRemaining.map { $0 as Any } ?? NSNull()

        let stockTotal: Any =
            record.stockTotal.map { $0 as Any } ?? NSNull()

        return [
            "kind": firestoreKind(record.kind),
            "title": record.title,
            "detail": record.detail,
            "times": ScheduleRules.times(record.times).joined(separator: ","),
            "start": record.start,
            "end": record.end,
            "place": record.place,
            "level": record.level,
            "reminderMinutes": record.reminderMinutes,
            "dayBefore": record.dayBefore,
            "archived": record.archived,
            "stockRemaining": stockRemaining,
            "unitsPerDose": record.unitsPerDose,
            "stockAlertAt": record.stockAlertAt,
            "stockTotal": stockTotal,
            "foodItems": record.foodItems
        ]
    }

    private func decodeRecord(
        id: String,
        data: [String: Any]
    ) -> HealthRecord? {
        guard
            let kindString = data["kind"] as? String,
            let kind = recordKind(kindString),
            let title = data["title"] as? String,
            let detail = data["detail"] as? String,
            let times = data["times"] as? String,
            let start = data["start"] as? String,
            let end = data["end"] as? String,
            let place = data["place"] as? String,
            let level = data["level"] as? String,
            let reminderMinutes = data["reminderMinutes"] as? Int,
            let dayBefore = data["dayBefore"] as? Bool,
            let archived = data["archived"] as? Bool
        else {
            return nil
        }

        return HealthRecord(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            times: times,
            start: start,
            end: end,
            place: place,
            level: level,
            reminderMinutes: reminderMinutes,
            dayBefore: dayBefore,
            archived: archived,
            stockRemaining: (data["stockRemaining"] as? NSNumber)?.intValue,
            unitsPerDose: (data["unitsPerDose"] as? NSNumber)?.intValue ?? 1,
            stockAlertAt: (data["stockAlertAt"] as? NSNumber)?.intValue ?? 5,
            stockTotal: (data["stockTotal"] as? NSNumber)?.intValue,
            foodItems: data["foodItems"] as? String ?? ""
        )
    }

    func fetchRecords() async throws -> [HealthRecord] {
        let snapshot = try await recordsCollection.getDocuments()

        return snapshot.documents.compactMap { document in
            decodeRecord(id: document.documentID, data: document.data())
        }
    }

    func saveRecord(_ record: HealthRecord) async throws {
        // Los registros nuevos y editados se validan en MediVidaStore.
        // Aquí también se pueden sincronizar citas históricas ya existentes.
        let document = recordsCollection.document(record.id)
        let snapshot = try await document.getDocument()

        if !snapshot.exists && record.archived {
            // Las reglas impiden crear directamente un registro archivado.
            var activeRecord = record
            activeRecord.archived = false
            try await document.setData(encodeRecord(activeRecord))
            try await document.updateData(["archived": true])
        } else {
            try await document.setData(encodeRecord(record))
        }
    }

    // MARK: - Perfil

    func fetchProfile() async throws -> PatientProfile? {
        let snapshot = try await userDocument.getDocument()

        guard snapshot.exists, let data = snapshot.data() else {
            return nil
        }

        guard
            let name = data["name"] as? String,
            let age = data["age"] as? String,
            let weight = data["weight"] as? String,
            let blood = data["blood"] as? String,
            let allergies = data["allergies"] as? String,
            let contact = data["contact"] as? String,
            let phone = data["phone"] as? String,
            let notifications = data["notifications"] as? Bool
        else {
            return nil
        }

        return PatientProfile(
            name: name,
            age: age,
            weight: weight,
            blood: blood,
            allergies: allergies,
            contact: contact,
            phone: phone,
            notifications: notifications
        )
    }

    func saveProfile(_ profile: PatientProfile) async throws {
        let name = profile.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard (2...100).contains(name.count) else {
            throw RuleError("El nombre debe tener entre 2 y 100 caracteres.")
        }

        let data: [String: Any] = [
            "name": name,
            "age": profile.age,
            "weight": profile.weight,
            "blood": profile.blood,
            "allergies": profile.allergies,
            "contact": profile.contact,
            "phone": profile.phone,
            "notifications": profile.notifications
        ]

        try await userDocument.setData(data)
    }

    // MARK: - Historial de dosis

    private func completionDocumentID(
        recordID: String,
        occurrence: String
    ) -> String {
        "\(recordID)_\(occurrence.replacingOccurrences(of: ":", with: "-"))"
    }

    private func encodeCompletion(
        _ completion: DoseCompletion
    ) -> [String: Any] {
        let milliseconds = Int64(
            completion.completedAt.timeIntervalSince1970 * 1000
        )

        return [
            "recordId": completion.recordID,
            "occurrence": completion.occurrence,
            "status": completion.status.rawValue,
            "at": milliseconds
        ]
    }

    private func decodeCompletion(
        _ data: [String: Any]
    ) -> DoseCompletion? {
        guard
            let recordID = data["recordId"] as? String,
            let occurrence = data["occurrence"] as? String,
            let statusValue = data["status"] as? String,
            let status = DoseStatus(rawValue: statusValue),
            let timestamp = data["at"] as? NSNumber
        else {
            return nil
        }

        return DoseCompletion(
            recordID: recordID,
            occurrence: occurrence,
            status: status,
            completedAt: Date(
                timeIntervalSince1970: Double(timestamp.int64Value) / 1000
            )
        )
    }

    func fetchCompletions() async throws -> [DoseCompletion] {
        let snapshot = try await completionsCollection.getDocuments()

        return snapshot.documents.compactMap { document in
            decodeCompletion(document.data())
        }
    }

    func saveCompletion(
        _ completion: DoseCompletion,
        updatedRecord: HealthRecord? = nil
    ) async throws {
        let eventID = completionDocumentID(
            recordID: completion.recordID,
            occurrence: completion.occurrence
        )

        let batch = database.batch()

        batch.setData(
            encodeCompletion(completion),
            forDocument: completionsCollection.document(eventID)
        )

        if let record = updatedRecord {
            batch.setData(
                encodeRecord(record),
                forDocument: recordsCollection.document(record.id)
            )
        }

        try await batch.commit()
    }
}
