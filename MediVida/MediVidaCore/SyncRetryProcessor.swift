import Foundation

/// Resultado de un intento de escritura de la cola de sincronización.
public struct SyncWriteAttempt {
    public let queue: SyncQueueState
    public let acknowledged: Bool
    public let errorMessage: String?

    public init(
        queue: SyncQueueState,
        acknowledged: Bool,
        errorMessage: String?
    ) {
        self.queue = queue
        self.acknowledged = acknowledged
        self.errorMessage = errorMessage
    }
}

/// Ejecuta escrituras y solo confirma los elementos cuando
/// la operación tiene éxito y el dato local sigue sin cambios.
@MainActor
public enum SyncRetryProcessor {

    public static func record(
        id: String,
        queue: SyncQueueState,
        write: () async throws -> Void,
        snapshotIsCurrent: () -> Bool
    ) async -> SyncWriteAttempt {
        do {
            try await write()
        } catch {
            return SyncWriteAttempt(
                queue: queue,
                acknowledged: false,
                errorMessage: error.localizedDescription
            )
        }

        var updatedQueue = queue
        let acknowledged = updatedQueue.acknowledgeRecord(
            id,
            writeSucceeded: true,
            snapshotIsCurrent: snapshotIsCurrent()
        )

        return SyncWriteAttempt(
            queue: updatedQueue,
            acknowledged: acknowledged,
            errorMessage: nil
        )
    }

    public static func completion(
        id: String,
        queue: SyncQueueState,
        write: () async throws -> Void,
        snapshotIsCurrent: () -> Bool
    ) async -> SyncWriteAttempt {
        do {
            try await write()
        } catch {
            return SyncWriteAttempt(
                queue: queue,
                acknowledged: false,
                errorMessage: error.localizedDescription
            )
        }

        var updatedQueue = queue
        let acknowledged = updatedQueue.acknowledgeCompletion(
            id,
            writeSucceeded: true,
            snapshotIsCurrent: snapshotIsCurrent()
        )

        return SyncWriteAttempt(
            queue: updatedQueue,
            acknowledged: acknowledged,
            errorMessage: nil
        )
    }

    public static func profile(
        queue: SyncQueueState,
        write: () async throws -> Void,
        snapshotIsCurrent: () -> Bool
    ) async -> SyncWriteAttempt {
        do {
            try await write()
        } catch {
            return SyncWriteAttempt(
                queue: queue,
                acknowledged: false,
                errorMessage: error.localizedDescription
            )
        }

        var updatedQueue = queue
        let acknowledged = updatedQueue.acknowledgeProfile(
            writeSucceeded: true,
            snapshotIsCurrent: snapshotIsCurrent()
        )

        return SyncWriteAttempt(
            queue: updatedQueue,
            acknowledged: acknowledged,
            errorMessage: nil
        )
    }
}
