import Foundation

/// Instantánea persistente del almacén de MediVida.
///
/// Incluye los datos de salud y la cola de elementos pendientes
/// para que puedan recuperarse después de cerrar y abrir la app.
public struct MediVidaSavedData: Codable {
    public var records: [HealthRecord]
    public var completions: [DoseCompletion]
    public var profile: PatientProfile

    public var pendingRecordIDs: [String]
    public var pendingCompletionIDs: [String]
    public var profilePending: Bool

    enum CodingKeys: String, CodingKey {
        case records
        case completions
        case profile
        case pendingRecordIDs
        case pendingCompletionIDs
        case profilePending
    }

    public init(
        records: [HealthRecord],
        completions: [DoseCompletion],
        profile: PatientProfile,
        pendingRecordIDs: [String] = [],
        pendingCompletionIDs: [String] = [],
        profilePending: Bool = false
    ) {
        self.records = records
        self.completions = completions
        self.profile = profile
        self.pendingRecordIDs = pendingRecordIDs
        self.pendingCompletionIDs = pendingCompletionIDs
        self.profilePending = profilePending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        records = try container.decode(
            [HealthRecord].self,
            forKey: .records
        )

        completions = try container.decode(
            [DoseCompletion].self,
            forKey: .completions
        )

        profile = try container.decode(
            PatientProfile.self,
            forKey: .profile
        )

        // Compatibilidad con archivos anteriores sin cola persistente.
        pendingRecordIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .pendingRecordIDs
        ) ?? []

        pendingCompletionIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .pendingCompletionIDs
        ) ?? []

        profilePending = try container.decodeIfPresent(
            Bool.self,
            forKey: .profilePending
        ) ?? false
    }
}
