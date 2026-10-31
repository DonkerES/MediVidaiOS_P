import Foundation

/// Contrato del repositorio usado por el proceso de sincronización.
/// Permite sustituir Firebase por un repositorio simulado en las pruebas.
@MainActor
public protocol MediVidaSyncRepository {
    func fetchRecords() async throws -> [HealthRecord]
    func saveRecord(_ record: HealthRecord) async throws

    func fetchCompletions() async throws -> [DoseCompletion]
    func saveCompletion(
        _ completion: DoseCompletion,
        updatedRecord: HealthRecord?
    ) async throws

    func fetchProfile() async throws -> PatientProfile?
    func saveProfile(_ profile: PatientProfile) async throws
}
