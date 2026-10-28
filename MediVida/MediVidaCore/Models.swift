import Foundation

public enum RecordKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case medicine = "Medicamento"
    case appointment = "Cita médica"
    case meal = "Comida"
    case restriction = "Alimento"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .medicine: "pills.fill"
        case .appointment: "calendar"
        case .meal: "fork.knife"
        case .restriction: "leaf.fill"
        }
    }
}

public enum DoseStatus: String, Codable, Hashable { case taken = "TAKEN", skipped = "SKIPPED" }
public enum FoodLevel: String, CaseIterable, Identifiable, Codable, Hashable {
    case permitted = "Permitido"
    case restricted = "Restringido"
    case prohibited = "Prohibido"
    case moderate = "Moderado"

    public var id: String { rawValue }
}

public struct HealthRecord: Codable, Identifiable, Hashable {
    public var id: String
    public var kind: RecordKind
    public var title: String
    public var detail: String
    public var times: String
    public var start: String
    public var end: String
    public var place: String
    public var level: String
    public var reminderMinutes: Int
    public var dayBefore: Bool
    public var archived: Bool
    public var stockRemaining: Int?
    public var unitsPerDose: Int
    public var stockAlertAt: Int
    public var stockTotal: Int?
    public var foodItems: String

    public init(id: String = UUID().uuidString, kind: RecordKind, title: String, detail: String = "", times: String = "08:00", start: String = DateText.string(from: .now), end: String = "", place: String = "", level: String = FoodLevel.permitted.rawValue, reminderMinutes: Int = 0, dayBefore: Bool = false, archived: Bool = false, stockRemaining: Int? = nil, unitsPerDose: Int = 1, stockAlertAt: Int = 5, stockTotal: Int? = nil, foodItems: String = "") {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.times = times
        self.start = start
        self.end = end
        self.place = place
        self.level = level
        self.reminderMinutes = reminderMinutes
        self.dayBefore = dayBefore
        self.archived = archived
        self.stockRemaining = stockRemaining
        self.unitsPerDose = unitsPerDose
        self.stockAlertAt = stockAlertAt
        self.stockTotal = stockTotal
        self.foodItems = foodItems
    }
}

public struct DoseCompletion: Codable, Identifiable, Hashable {
    public var recordID: String
    public var occurrence: String
    public var status: DoseStatus
    public var completedAt: Date
    public var id: String { "\(recordID)_\(occurrence)" }

    public init(recordID: String, occurrence: String, status: DoseStatus, completedAt: Date) {
        self.recordID = recordID
        self.occurrence = occurrence
        self.status = status
        self.completedAt = completedAt
    }
}

public struct PatientProfile: Codable {
    public var name: String
    public var age: String
    public var weight: String
    public var blood: String
    public var allergies: String
    public var contact: String
    public var phone: String
    public var notifications: Bool

    public init(name: String = "", age: String = "", weight: String = "", blood: String = "", allergies: String = "", contact: String = "", phone: String = "", notifications: Bool = true) {
        self.name = name
        self.age = age
        self.weight = weight
        self.blood = blood
        self.allergies = allergies
        self.contact = contact
        self.phone = phone
        self.notifications = notifications
    }
}

public struct ScheduledTask: Identifiable, Hashable {
    public var record: HealthRecord
    public var date: Date
    public var time: String
    public var id: String { "\(record.id)_\(occurrence)" }
    public var occurrence: String { "\(DateText.string(from: date))T\(time)" }

    public init(record: HealthRecord, date: Date, time: String) {
        self.record = record
        self.date = date
        self.time = time
    }
}

public enum DateText {
    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    public static func string(from date: Date) -> String { dateFormatter().string(from: date) }
    public static func date(from value: String) -> Date? { dateFormatter().date(from: value) }
    public static func time(_ value: String) -> Date? {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              bytes[0].isASCIIDigit, bytes[1].isASCIIDigit,
              bytes[3].isASCIIDigit, bytes[4].isASCIIDigit else { return nil }
        let hour = Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
        let minute = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute))
    }
    public static func timeString(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
    }
}

public enum ScheduleRules {
    public static func times(_ value: String) -> [String] {
        Array(Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })).sorted()
    }

    public static func validate(_ record: HealthRecord) throws {
        guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.title.count <= 100 else { throw RuleError("Escribe un nombre de hasta 100 caracteres.") }
        guard record.detail.count <= 1000, record.place.count <= 200, record.foodItems.count <= 2000 else {
            throw RuleError("Uno de los textos supera el máximo permitido.")
        }
        if record.kind == .restriction {
            guard FoodLevel(rawValue: record.level) != nil else { throw RuleError("Selecciona Permitido o Restringido.") }
            return
        }
        guard let start = DateText.date(from: record.start) else { throw RuleError("La fecha inicial no es válida.") }
        if record.kind == .appointment && Calendar.current.startOfDay(for: start) < Calendar.current.startOfDay(for: .now) {
            throw RuleError("La fecha de la cita debe ser hoy o posterior.")
        }
        if !record.end.isEmpty {
            guard let end = DateText.date(from: record.end), end >= start else { throw RuleError("La fecha final debe ser igual o posterior al inicio.") }
        }
        let entries = record.times.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !entries.isEmpty, entries.count <= 24, entries.allSatisfy({ DateText.time($0) != nil }),
              Set(entries).count == entries.count else { throw RuleError("Revisa los horarios; deben ser válidos y diferentes.") }
        if record.kind == .appointment && entries.count != 1 { throw RuleError("Una cita necesita una sola hora.") }
        if record.kind == .medicine && record.detail.trimmingCharacters(in: .whitespaces).isEmpty {
            throw RuleError("Indica la dosis y las instrucciones prescritas.")
        }
        if record.kind == .medicine {
            if let remaining = record.stockRemaining, !(0...100_000).contains(remaining) {
                throw RuleError("Las unidades disponibles deben estar entre 0 y 100 000.")
            }
            guard (1...1000).contains(record.unitsPerDose) else {
                throw RuleError("Las unidades por dosis deben estar entre 1 y 1 000.")
            }
            guard (0...100_000).contains(record.stockAlertAt) else {
                throw RuleError("El umbral de existencias debe estar entre 0 y 100 000.")
            }
            if let total = record.stockTotal {
                guard (0...100_000).contains(total), total >= (record.stockRemaining ?? 0) else {
                    throw RuleError("El total de referencia no puede ser menor que las unidades disponibles.")
                }
            }
        }
    }

    public static func tasks(records: [HealthRecord], on day: Date) -> [ScheduledTask] {
        let target = Calendar.current.startOfDay(for: day)
        return records.filter { record in
            guard !record.archived, record.kind != .restriction,
                  let start = DateText.date(from: record.start), target >= Calendar.current.startOfDay(for: start) else { return false }
            if !record.end.isEmpty, let end = DateText.date(from: record.end), target > Calendar.current.startOfDay(for: end) { return false }
            if record.kind == .appointment && target != Calendar.current.startOfDay(for: start) { return false }
            return true
        }.flatMap { record in
            times(record.times).compactMap { time -> ScheduledTask? in
                guard let parts = DateText.time(time),
                      let date = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: parts), minute: Calendar.current.component(.minute, from: parts), second: 0, of: target) else { return nil }
                return ScheduledTask(record: record, date: date, time: time)
            }
        }.sorted { $0.date < $1.date }
    }

    public static func stockAfterDose(_ record: HealthRecord) -> Int? {
        record.stockRemaining.map { max(0, $0 - record.unitsPerDose) }
    }

    public static func adherence(tasks: [ScheduledTask], completions: [DoseCompletion], on day: Date, now: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: now) else { return 0 }
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let cutoff = calendar.isDate(day, inSameDayAs: now) ? now : end
        let due = tasks.filter { $0.record.kind == .medicine && $0.date >= start && $0.date < end && $0.date <= cutoff }
        guard !due.isEmpty else { return 0 }
        let completedIDs = Set(completions.filter { $0.status == .taken }.map(\.id))
        let taken = due.filter { task in
            completedIDs.contains("\(task.record.id)_\(task.occurrence)")
        }.count
        return taken * 100 / due.count
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { (48...57).contains(self) }
}

public struct RuleError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
