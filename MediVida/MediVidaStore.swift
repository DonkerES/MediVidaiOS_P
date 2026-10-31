import Combine
import Foundation
import UserNotifications

@MainActor
final class MediVidaStore: ObservableObject {
    @Published private(set) var records: [HealthRecord] = []
    @Published private(set) var completions: [DoseCompletion] = []
    @Published var profile = PatientProfile()
    @Published var storageMessage = "Guardado en este dispositivo"
    private var storageLoadFailed = false
    private let ownerID: String
    private let repository: any MediVidaSyncRepository
    private var syncQueue = SyncQueueState()

    private var pendingRecordIDs: [String] {
        get { syncQueue.pendingRecordIDs }
        set { syncQueue.pendingRecordIDs = newValue }
    }

    private var pendingCompletionIDs: [String] {
        get { syncQueue.pendingCompletionIDs }
        set { syncQueue.pendingCompletionIDs = newValue }
    }

    private var profilePending: Bool {
        get { syncQueue.profilePending }
        set { syncQueue.profilePending = newValue }
    }
    private var syncInProgress = false
    private var syncRequestedAgain = false

    private var fileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("MediVida", isDirectory: true)
        .appendingPathComponent("Accounts", isDirectory: true)
        .appendingPathComponent(ownerID, isDirectory: true)
        .appendingPathComponent("health-data.json")
    }

    init(
        ownerID: String,
        repository: (any MediVidaSyncRepository)? = nil
    ) {
        self.ownerID = ownerID
        self.repository = repository
            ?? MediVidaFirestoreRepository(userID: ownerID)
        load()
    }

    func refreshNotifications() async {
        await rescheduleNotifications()
    }

    func syncFromCloud() async {
        if syncInProgress {
            syncRequestedAgain = true
            return
        }

        syncInProgress = true

        defer {
            syncInProgress = false

            if syncRequestedAgain {
                syncRequestedAgain = false
                Task {
                    await self.syncFromCloud()
                }
            }
        }

        guard !storageLoadFailed else {
            storageMessage =
                "Sincronización bloqueada para proteger los datos locales."
            return
        }

        storageMessage = "Sincronizando con Firebase..."

        let result = await MediVidaSyncCoordinator.synchronize(
            repository: repository,
            getSnapshot: {
                MediVidaSyncSnapshot(
                    records: self.records,
                    completions: self.completions,
                    profile: self.profile,
                    queue: self.syncQueue
                )
            },
            applySnapshot: { snapshot in
                self.records = snapshot.records
                self.completions = snapshot.completions
                self.profile = snapshot.profile
                self.syncQueue = snapshot.queue
            },
            persist: {
                try self.persist()
            }
        )

        await rescheduleNotifications()
        storageMessage = result
    }

    var activeMedicines: [HealthRecord] { records.filter { $0.kind == .medicine && !$0.archived } }
    var appointments: [HealthRecord] { records.filter { $0.kind == .appointment && !$0.archived }.sorted { $0.start < $1.start } }
    var meals: [HealthRecord] { records.filter { $0.kind == .meal && !$0.archived }.sorted { $0.times < $1.times } }
    var foods: [HealthRecord] { records.filter { $0.kind == .restriction && !$0.archived } }

    func tasks(on day: Date) -> [ScheduledTask] { ScheduleRules.tasks(records: records, on: day) }

    func medicineTasks(on day: Date) -> [ScheduledTask] {
        tasks(on: day).filter { $0.record.kind == .medicine }
    }

    func completion(for task: ScheduledTask) -> DoseCompletion? {
        completions.first { $0.recordID == task.record.id && $0.occurrence == task.occurrence }
    }

    func adherence(on day: Date = .now) -> Int {
        ScheduleRules.adherence(tasks: tasks(on: day), completions: completions, on: day, now: .now)
    }

    func save(_ record: HealthRecord) throws {
        try ScheduleRules.validate(record)

        let previousRecords = records
        let previousQueue = pendingRecordIDs

        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }

        if !pendingRecordIDs.contains(record.id) {
            pendingRecordIDs.append(record.id)
        }

        do {
            try persist()
        } catch {
            records = previousRecords
            pendingRecordIDs = previousQueue
            throw error
        }

        Task {
            await syncFromCloud()
        }
    }

    func archive(_ record: HealthRecord) throws {
        guard let index = records.firstIndex(
            where: { $0.id == record.id }
        ) else {
            return
        }

        let previousRecords = records
        let previousQueue = pendingRecordIDs

        records[index].archived = true

        if !pendingRecordIDs.contains(record.id) {
            pendingRecordIDs.append(record.id)
        }

        do {
            try persist()
        } catch {
            records = previousRecords
            pendingRecordIDs = previousQueue
            throw error
        }

        Task {
            await syncFromCloud()
        }
    }

    func updateProfile(_ profile: PatientProfile) throws {
        let normalizedProfile = try ProfileRules.validated(profile)

        let previousProfile = self.profile
        let previousPending = profilePending

        self.profile = normalizedProfile
        profilePending = true

        do {
            try persist()
        } catch {
            self.profile = previousProfile
            profilePending = previousPending
            throw error
        }

        Task {
            await syncFromCloud()
        }
    }

    func complete(_ task: ScheduledTask, status: DoseStatus) throws {
        guard task.record.kind == .medicine else {
            throw RuleError(
                "Solo puedes registrar como tomada u omitida una dosis de medicamento."
            )
        }

        guard task.date <= .now else {
            throw RuleError("La hora de esta tarea todavía no llegó.")
        }

        guard completion(for: task) == nil else { return }

        let previousCompletions = completions
        let previousRecords = records
        let previousCompletionQueue = pendingCompletionIDs
        let previousRecordQueue = pendingRecordIDs

        let newCompletion = DoseCompletion(
            recordID: task.record.id,
            occurrence: task.occurrence,
            status: status,
            completedAt: .now
        )

        completions.append(newCompletion)

        var inventoryChanged = false

        if status == .taken,
           let index = records.firstIndex(
               where: { $0.id == task.record.id }
           ),
           records[index].kind == .medicine,
           records[index].stockRemaining != nil {
            records[index].stockRemaining =
                ScheduleRules.stockAfterDose(records[index])
            inventoryChanged = true
        }

        if !pendingCompletionIDs.contains(newCompletion.id) {
            pendingCompletionIDs.append(newCompletion.id)
        }

        if inventoryChanged
            && !pendingRecordIDs.contains(task.record.id) {
            pendingRecordIDs.append(task.record.id)
        }

        do {
            try persist()
        } catch {
            completions = previousCompletions
            records = previousRecords
            pendingCompletionIDs = previousCompletionQueue
            pendingRecordIDs = previousRecordQueue
            throw error
        }

        Task {
            await syncFromCloud()
        }
    }

    func askForNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { storageMessage = "No se pudieron activar los avisos"; return false }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let saved = try JSONDecoder().decode(MediVidaSavedData.self, from: data)
            records = saved.records
            completions = saved.completions
            profile = saved.profile
            pendingRecordIDs = saved.pendingRecordIDs
            pendingCompletionIDs = saved.pendingCompletionIDs
            profilePending = saved.profilePending
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            storageLoadFailed = true
            storageMessage = "No se pudieron recuperar los datos. No guardaremos cambios para evitar sobrescribirlos."
        }
    }

    private func persist() throws {
        guard !storageLoadFailed else {
            throw RuleError("No se pudo leer el archivo de datos anterior. Los cambios se bloquearon para proteger la información existente.")
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(MediVidaSavedData(records: records, completions: completions, profile: profile, pendingRecordIDs: pendingRecordIDs, pendingCompletionIDs: pendingCompletionIDs, profilePending: profilePending))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageMessage = "Guardado en este dispositivo"
        } catch {
            storageMessage = "No se pudieron guardar los cambios"
            throw error
        }
    }

    private func rescheduleNotifications() async {
        let center = UNUserNotificationCenter.current()
        let managedPrefix = "medivida_"
        let calendar = Calendar.current
        var requests: [UNNotificationRequest] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) else { continue }
            for task in tasks(on: day) where task.date > .now && completion(for: task) == nil {
                var fireDates = [task.date]
                if task.record.kind == .appointment {
                    if task.record.reminderMinutes > 0,
                       let lead = calendar.date(byAdding: .minute, value: -task.record.reminderMinutes, to: task.date), lead > .now { fireDates.append(lead) }
                    if task.record.dayBefore,
                       let lead = calendar.date(byAdding: .day, value: -1, to: task.date), lead > .now { fireDates.append(lead) }
                }
                for (index, fireDate) in fireDates.enumerated() {
                    if requests.count >= 60 { break }
                    let content = UNMutableNotificationContent()
                    switch task.record.kind {
                    case .medicine: content.title = "Hora de tu medicamento"
                    case .appointment: content.title = "Recordatorio de cita"
                    case .meal: content.title = "Recordatorio de comida"
                    case .restriction: content.title = "Recordatorio de MediVida"
                    }
                    content.body = "\(task.record.title) · \(task.record.detail)"
                    content.sound = .default
                    content.userInfo = ["recordID": task.record.id, "occurrence": task.occurrence]
                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    requests.append(UNNotificationRequest(identifier: "\(managedPrefix)\(task.id)_\(index)", content: content, trigger: trigger))
                }
                if requests.count >= 60 { break }
            }
            if requests.count >= 60 { break }
        }
        let existing = await center.pendingNotificationRequests()
        let managedIDs = existing.map(\.identifier).filter { $0.hasPrefix(managedPrefix) }
        guard !requests.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: managedIDs)
            return
        }
        let settings = await center.notificationSettings()
        let granted: Bool
        if settings.authorizationStatus == .notDetermined { granted = await askForNotifications() }
        else { granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional }
        guard granted else {
            center.removePendingNotificationRequests(withIdentifiers: managedIDs)
            let currentSettings = await center.notificationSettings()
            if currentSettings.authorizationStatus == .denied {
                storageMessage = "Los avisos están desactivados en Ajustes"
            }
            return
        }
        center.removePendingNotificationRequests(withIdentifiers: managedIDs)
        var failedCount = 0
        var lastError: Error?
        for request in requests {
            do { try await center.add(request) }
            catch { failedCount += 1; lastError = error }
        }
        if failedCount > 0 {
            storageMessage = "Fallaron \(failedCount) avisos: \(lastError?.localizedDescription ?? "error desconocido")"
        } else {
            storageMessage = "Avisos actualizados (\(requests.count)) · Guardado en este dispositivo"
        }
    }
}
