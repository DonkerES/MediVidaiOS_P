import Foundation
import Combine

/// Estado de la cola de sincronización de MediVida.
public struct SyncQueueState: Equatable {
    public var pendingRecordIDs: [String]
    public var pendingCompletionIDs: [String]
    public var profilePending: Bool

    public init(
        pendingRecordIDs: [String] = [],
        pendingCompletionIDs: [String] = [],
        profilePending: Bool = false
    ) {
        self.pendingRecordIDs = pendingRecordIDs
        self.pendingCompletionIDs = pendingCompletionIDs
        self.profilePending = profilePending
    }

    public mutating func enqueueRecord(_ id: String) {
        guard !pendingRecordIDs.contains(id) else { return }
        pendingRecordIDs.append(id)
    }

    public mutating func enqueueCompletion(_ id: String) {
        guard !pendingCompletionIDs.contains(id) else { return }
        pendingCompletionIDs.append(id)
    }

    public mutating func markProfilePending() {
        profilePending = true
    }

    /// Solo retira el registro después de una escritura correcta
    /// y si el registro local no cambió durante la operación.
    @discardableResult
    public mutating func acknowledgeRecord(
        _ id: String,
        writeSucceeded: Bool,
        snapshotIsCurrent: Bool
    ) -> Bool {
        guard writeSucceeded,
              snapshotIsCurrent,
              pendingRecordIDs.contains(id) else {
            return false
        }

        pendingRecordIDs.removeAll { $0 == id }
        return true
    }

    /// Solo retira la toma después de una escritura correcta
    /// y si la toma local no cambió durante la operación.
    @discardableResult
    public mutating func acknowledgeCompletion(
        _ id: String,
        writeSucceeded: Bool,
        snapshotIsCurrent: Bool
    ) -> Bool {
        guard writeSucceeded,
              snapshotIsCurrent,
              pendingCompletionIDs.contains(id) else {
            return false
        }

        pendingCompletionIDs.removeAll { $0 == id }
        return true
    }

    /// Solo limpia la marca del perfil si la escritura tuvo éxito
    /// y el perfil local sigue siendo el mismo que se envió.
    @discardableResult
    public mutating func acknowledgeProfile(
        writeSucceeded: Bool,
        snapshotIsCurrent: Bool
    ) -> Bool {
        guard writeSucceeded,
              snapshotIsCurrent,
              profilePending else {
            return false
        }

        profilePending = false
        return true
    }
}
