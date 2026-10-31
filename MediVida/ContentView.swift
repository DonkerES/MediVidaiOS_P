import SwiftUI

enum MediVidaStyle {
    static let teal = Color(red: 0.02, green: 0.58, blue: 0.63)
    static let green = Color(red: 0.02, green: 0.61, blue: 0.43)
    static let purple = Color(red: 0.43, green: 0.24, blue: 0.78)
    static let orange = Color(red: 0.91, green: 0.48, blue: 0.08)
    static let red = Color(red: 0.78, green: 0.20, blue: 0.24)
    static let ink = Color(red: 0.10, green: 0.17, blue: 0.28)
    static let muted = Color(red: 0.43, green: 0.50, blue: 0.60)
    static let canvas = Color(red: 0.95, green: 0.97, blue: 0.99)
}

private struct EditorRoute: Identifiable {
    var kind: RecordKind
    var record: HealthRecord?
    var id: String { record?.id ?? "new-\(kind.rawValue)" }
}

struct MediVidaRootView: View {
    @EnvironmentObject private var store: MediVidaStore
    @State private var editor: EditorRoute?
    @State private var profileEditor = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeScreen(onAdd: add) }
                .tabItem { Label("Inicio", systemImage: "house.fill") }.tag(0)
            NavigationStack { MedicationScreen(onAdd: add) }
                .tabItem { Label("Medicación", systemImage: "pills.fill") }.tag(1)
            NavigationStack { AppointmentScreen(onAdd: add) }
                .tabItem { Label("Citas", systemImage: "calendar") }.tag(2)
            NavigationStack { NutritionScreen(onAdd: add) }
                .tabItem { Label("Nutrición", systemImage: "fork.knife") }.tag(3)
            NavigationStack { ProfileScreen(onEdit: { profileEditor = true }) }
                .tabItem { Label("Perfil", systemImage: "person.fill") }.tag(4)
        }
        .sheet(item: $editor) { route in
            NavigationStack { RecordEditorView(kind: route.kind, existing: route.record) }
        }
        .sheet(isPresented: $profileEditor) {
            NavigationStack { ProfileEditorView() }
        }
    }

    private func add(_ kind: RecordKind) { editor = EditorRoute(kind: kind, record: nil) }
}

private struct AddRecordMenu: View {
    var onAdd: (RecordKind) -> Void
    var body: some View {
        Menu {
            ForEach(RecordKind.allCases) { kind in
                Button { onAdd(kind) } label: { Label(kind.rawValue, systemImage: kind.symbol) }
            }
        } label: { Image(systemName: "plus.circle.fill").font(.title2) }
        .accessibilityLabel("Agregar registro")
    }
}

private struct PageBackground<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(16)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(MediVidaStyle.canvas.ignoresSafeArea())
    }
}

private struct SectionTitle: View {
    var title: String
    var action: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(MediVidaStyle.ink)
            Spacer()
            if let action {
                Button("Ver todo", action: action).font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct Surface<Content: View>: View {
    var tint: Color = .white
    let content: Content
    init(tint: Color = .white, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MediVidaStyle.ink.opacity(0.07), lineWidth: 1))
    }
}

private struct HomeScreen: View {
    @EnvironmentObject private var store: MediVidaStore
    var onAdd: (RecordKind) -> Void

    private var todayTasks: [ScheduledTask] { store.tasks(on: .now) }
    private var todayMedicineTasks: [ScheduledTask] { todayTasks.filter { $0.record.kind == .medicine } }
    private var nextAppointment: HealthRecord? {
        store.appointments.first { record in
            guard let day = DateText.date(from: record.start) else { return false }
            return Calendar.current.startOfDay(for: day) >= Calendar.current.startOfDay(for: .now)
        }
    }
    private var stockAlerts: [HealthRecord] {
        store.activeMedicines.filter { record in
            guard let stock = record.stockRemaining else { return false }
            return stock <= record.stockAlertAt
        }
    }

    var body: some View {
        PageBackground {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                Text("Hola, \(store.profile.name.isEmpty ? "bienvenido" : store.profile.name)")
                    .font(.title2.bold()).foregroundStyle(.white)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [MediVidaStyle.teal, MediVidaStyle.green], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 10) {
                MetricTile(value: "\(todayMedicineTasks.filter { store.completion(for: $0) == nil }.count)", label: "dosis pendientes", tint: MediVidaStyle.teal)
                MetricTile(value: "\(store.appointments.count)", label: "citas", tint: MediVidaStyle.green)
                MetricTile(value: "\(store.adherence())%", label: "adherencia", tint: MediVidaStyle.purple)
            }

            SectionTitle(title: "Adherencia de hoy")
            Surface {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(MediVidaStyle.canvas, lineWidth: 10)
                        Circle().trim(from: 0, to: CGFloat(store.adherence()) / 100)
                            .stroke(adherenceColor(store.adherence()), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(store.adherence())%").font(.headline.bold()).foregroundStyle(MediVidaStyle.ink)
                    }.frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.activeMedicines.prefix(3)) { medicine in
                            let doses = todayTasks.filter { $0.record.id == medicine.id }
                            let done = doses.filter { store.completion(for: $0)?.status == .taken }.count
                            HStack {
                                Text(medicine.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                Text("\(done)/\(doses.count)").font(.caption).foregroundStyle(MediVidaStyle.muted)
                            }
                            ProgressView(value: doses.isEmpty ? 0 : Double(done) / Double(doses.count)).tint(MediVidaStyle.teal)
                        }
                        if store.activeMedicines.isEmpty { Text("Agrega un medicamento para iniciar el seguimiento.").font(.subheadline).foregroundStyle(MediVidaStyle.muted) }
                    }
                }
            }

            SectionTitle(title: "Agenda de hoy")
            if todayTasks.isEmpty {
                EmptySurface(text: "No hay tareas programadas para hoy. Usa + para agregar un tratamiento, cita o comida.")
            } else {
                ForEach(todayTasks) { task in TaskRow(task: task) }
            }

            if let appointment = nextAppointment {
                SectionTitle(title: "Próxima cita")
                RecordCard(record: appointment, accent: MediVidaStyle.green) {
                    Text("\(DateText.date(from: appointment.start)?.formatted(date: .abbreviated, time: .omitted) ?? appointment.start) · \(ScheduleRules.times(appointment.times).first ?? "")")
                        .font(.subheadline).foregroundStyle(MediVidaStyle.muted)
                    if !appointment.place.isEmpty { Label(appointment.place, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(MediVidaStyle.muted) }
                }
            }

            if !stockAlerts.isEmpty {
                SectionTitle(title: "Avisos de stock")
                ForEach(stockAlerts) { medicine in
                    Surface(tint: Color.orange.opacity(0.08)) {
                        Label("\(medicine.title): quedan \(medicine.stockRemaining ?? 0)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(MediVidaStyle.orange).font(.subheadline.weight(.semibold))
                    }
                }
            }
            Text(store.storageMessage).font(.caption).foregroundStyle(MediVidaStyle.muted).frame(maxWidth: .infinity)
        }
        .navigationTitle("MediVida")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AddRecordMenu(onAdd: onAdd) } }
    }
}

private struct MetricTile: View {
    var value: String
    var label: String
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title3.bold()).foregroundStyle(MediVidaStyle.ink)
            Text(label).font(.caption).foregroundStyle(MediVidaStyle.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private func adherenceColor(_ value: Int) -> Color {
    if value == 100 { return MediVidaStyle.green }
    if value >= 70 { return MediVidaStyle.orange }
    if value >= 50 { return Color.yellow }
    return MediVidaStyle.red
}

private struct TaskRow: View {
    @EnvironmentObject private var store: MediVidaStore
    var task: ScheduledTask
    @State private var error: String?
    var body: some View {
        Surface {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.record.kind.symbol).font(.title3).foregroundStyle(kindColor(task.record.kind)).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(task.record.title).font(.subheadline.bold()); Spacer(); Text(task.time).font(.subheadline.monospacedDigit()).foregroundStyle(MediVidaStyle.muted) }
                    Text(task.record.detail.isEmpty ? task.record.kind.rawValue : task.record.detail).font(.caption).foregroundStyle(MediVidaStyle.muted)
                    if task.record.kind != .medicine {
                        Text(task.record.kind.rawValue).font(.caption.weight(.medium)).foregroundStyle(kindColor(task.record.kind))
                    } else if let result = store.completion(for: task) {
                        Label(result.status == .taken ? "Tomada" : "Omitida", systemImage: result.status == .taken ? "checkmark.circle.fill" : "minus.circle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(result.status == .taken ? MediVidaStyle.green : MediVidaStyle.muted)
                    } else if task.date <= .now {
                        HStack {
                            Button("Tomada") { complete(.taken) }.buttonStyle(.borderedProminent).tint(MediVidaStyle.green)
                            Button("Omitir") { complete(.skipped) }.buttonStyle(.bordered)
                        }.font(.caption)
                    } else {
                        Text("Próxima").font(.caption.weight(.medium)).foregroundStyle(MediVidaStyle.teal)
                    }
                }
            }
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func complete(_ status: DoseStatus) {
        do { try store.complete(task, status: status) } catch { self.error = error.localizedDescription }
    }
}

private struct MedicationScreen: View {
    @EnvironmentObject private var store: MediVidaStore
    var onAdd: (RecordKind) -> Void
    @State private var selection = 0
    @State private var historyDate = Date.now
    @State private var editing: HealthRecord?
    @State private var alertText: String?

    var body: some View {
        PageBackground {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mis medicamentos").font(.title2.bold()).foregroundStyle(.white)
                    Text("\(store.adherence())% · adherencia de hoy").font(.subheadline).foregroundStyle(.white.opacity(0.86))
                }
                Spacer()
                Image(systemName: "pills.fill").font(.title).foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
            .background(LinearGradient(colors: [Color(red: 0.02, green: 0.36, blue: 0.49), MediVidaStyle.teal], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))

            Picker("Sección", selection: $selection) {
                Text("Pauta del día").tag(0)
                Text("Historial").tag(1)
                Text("Inventario").tag(2)
            }.pickerStyle(.segmented)

            if selection == 0 { dosePlan }
            else if selection == 1 { history }
            else { inventory }
        }
        .navigationTitle("Medicación")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AddRecordMenu(onAdd: onAdd) } }
        .sheet(item: $editing) { record in NavigationStack { RecordEditorView(kind: record.kind, existing: record) } }
        .alert("No se pudo actualizar", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK") { alertText = nil }
        } message: { Text(alertText ?? "") }
    }

    private var dosePlan: some View {
        Group {
            SectionTitle(title: "PAUTA DE HOY")
            if store.activeMedicines.isEmpty { EmptySurface(text: "Agrega tu primer medicamento con el botón +.") }
            ForEach(store.activeMedicines) { medicine in
                RecordCard(record: medicine, accent: MediVidaStyle.teal) {
                    Text(medicine.detail).font(.subheadline).foregroundStyle(MediVidaStyle.muted)
                    let doses = store.medicineTasks(on: .now).filter { $0.record.id == medicine.id }
                    if doses.isEmpty { Text("Sin dosis para hoy").font(.caption).foregroundStyle(MediVidaStyle.muted) }
                    ForEach(doses) { task in DosePill(task: task) }
                    if let stock = medicine.stockRemaining { StockLine(record: medicine, stock: stock) }
                }
                .contextMenu { Button("Editar", systemImage: "pencil") { editing = medicine }; Button("Archivar", systemImage: "archivebox", role: .destructive) { archive(medicine) } }
            }
        }
    }

    private var history: some View {
        Group {
            SectionTitle(title: "HISTORIAL POR DÍA")
            DatePicker("Día", selection: $historyDate, displayedComponents: .date).datePickerStyle(.graphical)
            let doses = store.medicineTasks(on: historyDate)
            if doses.isEmpty { EmptySurface(text: "No había dosis programadas para este día.") }
            ForEach(doses) { task in
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.record.title).font(.subheadline.bold())
                            Text("\(task.time) · \(task.record.detail)").font(.caption).foregroundStyle(MediVidaStyle.muted)
                        }
                        Spacer()
                        let result = store.completion(for: task)
                        Label(result?.status == .taken ? "Tomada" : result?.status == .skipped ? "Omitida" : "Sin registro", systemImage: result?.status == .taken ? "checkmark.circle.fill" : "circle")
                            .font(.caption).foregroundStyle(result?.status == .taken ? MediVidaStyle.green : MediVidaStyle.muted)
                    }
                }
            }
        }
    }

    private var inventory: some View {
        Group {
            SectionTitle(title: "MI INVENTARIO")
            if store.activeMedicines.isEmpty { EmptySurface(text: "Todavía no tienes medicamentos en el inventario.") }
            ForEach(store.activeMedicines) { medicine in
                RecordCard(record: medicine, accent: kindColor(.medicine)) {
                    Text(medicine.detail).font(.subheadline).foregroundStyle(MediVidaStyle.muted)
                    Label(ScheduleRules.times(medicine.times).joined(separator: "  ·  "), systemImage: "clock")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(MediVidaStyle.ink)
                    Text("Desde \(DateText.date(from: medicine.start)?.formatted(date: .long, time: .omitted) ?? medicine.start)")
                        .font(.caption).foregroundStyle(MediVidaStyle.muted)
                    if let stock = medicine.stockRemaining { StockLine(record: medicine, stock: stock) }
                    Button { editing = medicine } label: { Label("Editar pauta", systemImage: "pencil") }.font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func archive(_ record: HealthRecord) { do { try store.archive(record) } catch { alertText = error.localizedDescription } }
}

private struct DosePill: View {
    @EnvironmentObject private var store: MediVidaStore
    var task: ScheduledTask
    var body: some View {
        let completion = store.completion(for: task)
        HStack {
            Image(systemName: completion?.status == .taken ? "checkmark.circle.fill" : completion?.status == .skipped ? "minus.circle" : "circle")
            Text(task.time).font(.subheadline.monospacedDigit().weight(.semibold))
            Spacer()
            Text(completion?.status == .taken ? "Tomada" : completion?.status == .skipped ? "Omitida" : task.date <= .now ? "Pendiente" : "Próxima")
                .font(.caption).foregroundStyle(completion?.status == .taken ? MediVidaStyle.green : MediVidaStyle.muted)
        }
        .padding(10)
        .background((completion?.status == .taken ? MediVidaStyle.green : MediVidaStyle.teal).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StockLine: View {
    var record: HealthRecord
    var stock: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(stock), total: Double(max(record.stockTotal ?? stock, 1))).tint(stock <= record.stockAlertAt ? MediVidaStyle.orange : MediVidaStyle.teal)
            HStack {
                Text(stock <= record.stockAlertAt ? "Stock bajo" : "Existencias")
                Spacer()
                Text("\(stock) de \(record.stockTotal ?? stock)")
            }.font(.caption).foregroundStyle(stock <= record.stockAlertAt ? MediVidaStyle.orange : MediVidaStyle.muted)
        }
    }
}

private struct AppointmentScreen: View {
    @EnvironmentObject private var store: MediVidaStore
    var onAdd: (RecordKind) -> Void
    @State private var month = Date.now
    @State private var selectedDay: Date?
    @State private var editing: HealthRecord?
    @State private var alertText: String?
    private var visibleAppointments: [HealthRecord] {
        store.appointments.filter { record in
            guard let day = DateText.date(from: record.start) else { return false }
            let sameMonth = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
            return sameMonth && (selectedDay == nil || Calendar.current.isDate(day, inSameDayAs: selectedDay!))
        }
    }
    var body: some View {
        PageBackground {
            HStack(spacing: 10) {
                MetricTile(value: "\(store.appointments.filter { (DateText.date(from: $0.start) ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }.count)", label: "citas pendientes", tint: MediVidaStyle.green)
                MetricTile(value: nextDateLabel, label: "próxima cita", tint: MediVidaStyle.teal)
            }
            SectionTitle(title: "CALENDARIO DE CITAS")
            DatePicker("Selecciona un día", selection: $month, displayedComponents: .date).datePickerStyle(.graphical)
                .onChange(of: month) { _, value in selectedDay = value }
            HStack {
                Button("Todo el mes") { selectedDay = nil }
                Spacer()
                Text(selectedDay?.formatted(date: .complete, time: .omitted) ?? month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(MediVidaStyle.muted)
            }
            SectionTitle(title: "CITAS MÉDICAS")
            if visibleAppointments.isEmpty { EmptySurface(text: "No hay citas en este día o mes.") }
            ForEach(visibleAppointments) { appointment in
                RecordCard(record: appointment, accent: MediVidaStyle.green) {
                    Text("\(DateText.date(from: appointment.start)?.formatted(date: .complete, time: .omitted) ?? appointment.start) · \(ScheduleRules.times(appointment.times).first ?? "")")
                        .font(.subheadline).foregroundStyle(MediVidaStyle.muted)
                    if !appointment.place.isEmpty { Label(appointment.place, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(MediVidaStyle.muted) }
                    if !appointment.detail.isEmpty { Text(appointment.detail).font(.subheadline).foregroundStyle(MediVidaStyle.ink) }
                    HStack {
                        Button { editing = appointment } label: { Label("Editar", systemImage: "pencil") }
                        Spacer()
                        Button(role: .destructive) { archive(appointment) } label: { Label("Cancelar", systemImage: "xmark.circle") }
                    }.font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationTitle("Citas médicas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AddRecordMenu(onAdd: onAdd) } }
        .sheet(item: $editing) { record in NavigationStack { RecordEditorView(kind: record.kind, existing: record) } }
        .alert("No se pudo actualizar", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) { Button("OK") { alertText = nil } } message: { Text(alertText ?? "") }
    }
    private var nextDateLabel: String {
        guard let next = store.appointments.first(where: { (DateText.date(from: $0.start) ?? .distantPast) >= Calendar.current.startOfDay(for: .now) }),
              let date = DateText.date(from: next.start) else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
    private func archive(_ record: HealthRecord) { do { try store.archive(record) } catch { alertText = error.localizedDescription } }
}

private struct NutritionScreen: View {
    @EnvironmentObject private var store: MediVidaStore
    var onAdd: (RecordKind) -> Void
    @State private var filter = "Todos"
    @State private var editing: HealthRecord?
    @State private var alertText: String?
    private var visibleFoods: [HealthRecord] {
        store.foods.filter { filter == "Todos" || $0.level == filter }
    }
    var body: some View {
        PageBackground {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nutrición").font(.title2.bold()).foregroundStyle(.white)
                Text("Tus pautas de alimentación").font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [MediVidaStyle.purple, Color(red: 0.56, green: 0.34, blue: 0.81)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))

            SectionTitle(title: "PLAN DE COMIDAS")
            if store.meals.isEmpty { EmptySurface(text: "Agrega tus horarios e indicaciones de comidas con +.") }
            ForEach(store.meals) { meal in
                RecordCard(record: meal, accent: MediVidaStyle.purple) {
                    Text(meal.detail).font(.subheadline).foregroundStyle(MediVidaStyle.ink)
                    Label("\(ScheduleRules.times(meal.times).joined(separator: " · ")) · desde \(DateText.date(from: meal.start)?.formatted(date: .abbreviated, time: .omitted) ?? meal.start)", systemImage: "clock")
                        .font(.caption).foregroundStyle(MediVidaStyle.muted)
                    HStack {
                        Button { editing = meal } label: { Label("Editar", systemImage: "pencil") }
                        Spacer()
                        Button(role: .destructive) { archive(meal) } label: { Label("Archivar", systemImage: "archivebox") }
                    }.font(.subheadline.weight(.semibold))
                }
            }

            SectionTitle(title: "ALIMENTOS")
            Picker("Mostrar", selection: $filter) {
                ForEach(["Todos", FoodLevel.permitted.rawValue, FoodLevel.restricted.rawValue], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            if visibleFoods.isEmpty { EmptySurface(text: "Agrega categorías y alimentos indicados por tu profesional de salud.") }
            ForEach(visibleFoods) { category in
                DisclosureGroup {
                    Text(category.foodItems.isEmpty ? "Aún no hay alimentos en esta categoría." : category.foodItems)
                        .font(.subheadline).foregroundStyle(MediVidaStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
                    if !category.detail.isEmpty { Label(category.detail, systemImage: "text.quote").font(.caption).foregroundStyle(MediVidaStyle.muted) }
                    HStack {
                        Button { editing = category } label: { Label("Editar", systemImage: "pencil") }
                        Spacer()
                        Button(role: .destructive) { archive(category) } label: { Label("Archivar", systemImage: "archivebox") }
                    }.font(.subheadline.weight(.semibold))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.level == FoodLevel.permitted.rawValue ? "checkmark.circle.fill" : "nosign")
                            .font(.title3).foregroundStyle(category.level == FoodLevel.permitted.rawValue ? MediVidaStyle.green : MediVidaStyle.red)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title).font(.subheadline.bold()).foregroundStyle(MediVidaStyle.ink)
                            Text(category.level).font(.caption).foregroundStyle(MediVidaStyle.muted)
                        }
                    }
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("Nutrición")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AddRecordMenu(onAdd: onAdd) } }
        .sheet(item: $editing) { record in NavigationStack { RecordEditorView(kind: record.kind, existing: record) } }
        .alert("No se pudo actualizar", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) { Button("OK") { alertText = nil } } message: { Text(alertText ?? "") }
    }
    private func archive(_ record: HealthRecord) { do { try store.archive(record) } catch { alertText = error.localizedDescription } }
}

private struct ProfileScreen: View {
    @EnvironmentObject private var store: MediVidaStore
    @EnvironmentObject private var auth: MediVidaAuthStore
    @State private var isSyncing = false
    var onEdit: () -> Void
    var body: some View {
        PageBackground {
            VStack(alignment: .leading, spacing: 5) {
                Text("Tu información").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                Text("Perfil").font(.title2.bold()).foregroundStyle(.white)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [MediVidaStyle.teal, MediVidaStyle.green], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            SectionTitle(title: "DATOS PERSONALES")
            Surface {
                ProfileLine(label: "Nombre", value: store.profile.name)
                ProfileLine(label: "Edad", value: store.profile.age.isEmpty ? "Sin registrar" : "\(store.profile.age) años")
                ProfileLine(label: "Peso", value: store.profile.weight.isEmpty ? "Sin registrar" : "\(store.profile.weight) kg")
                ProfileLine(label: "Tipo de sangre", value: store.profile.blood.isEmpty ? "Sin registrar" : store.profile.blood)
                ProfileLine(label: "Alergias", value: store.profile.allergies.isEmpty ? "Ninguna registrada" : store.profile.allergies)
                ProfileLine(label: "Contacto", value: store.profile.contact.isEmpty ? "Sin registrar" : "\(store.profile.contact) \(store.profile.phone)")
                Button(action: onEdit) { Label("Editar perfil", systemImage: "pencil") }.padding(.top, 4)
            }
            SectionTitle(title: "SEGURIDAD Y DATOS")
            Surface {
                Label(
                    store.storageMessage,
                    systemImage: "iphone.and.arrow.right.outward"
                )
                .font(.subheadline)

                Text(
                    "Los registros se guardan localmente y están separados "
                    + "por cuenta. La sincronización con Cloud Firestore "
                    + "todavía no está activada."
                )
                .font(.caption)
                .foregroundStyle(MediVidaStyle.muted)

                Button {
                    Task {
                        isSyncing = true
                        await store.syncFromCloud()
                        isSyncing = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }

                        Text(
                            isSyncing
                            ? "Sincronizando..."
                            : "Sincronizar ahora"
                        )
                    }
                }
                .disabled(isSyncing)
                .padding(.top, 6)

                Button(role: .destructive) {
                    Task {
                        await auth.signOut()
                    }
                } label: {
                    Label(
                        "Cerrar sesión",
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                }
                .padding(.top, 6)
            }
            NavigationLink {
                AboutScreen()
            } label: {
                Label("Acerca de MediVida y créditos", systemImage: "info.circle")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            Text("MediVida organiza información de salud y no sustituye la valoración de un profesional.")
                .font(.caption).foregroundStyle(MediVidaStyle.muted)
        }
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileLine: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(MediVidaStyle.muted)
            Text(value).font(.subheadline).foregroundStyle(MediVidaStyle.ink)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AboutScreen: View {
    var body: some View {
        PageBackground {
            Text("MediVida").font(.largeTitle.bold()).foregroundStyle(MediVidaStyle.teal)
            Surface { Text("Tu rutina de salud en un lugar").font(.headline); Text("Organiza medicamentos, citas médicas y pautas de alimentación. Registra dosis y consulta su historial.").font(.subheadline).foregroundStyle(MediVidaStyle.muted) }
            Surface { Text("Equipo de desarrollo").font(.headline); Text("Julian Andres Narváez Cerón\nSebastian Alejandro Muñoz").font(.subheadline.weight(.semibold)) }
            Text("Versión iOS de MediVida. Los horarios y dosis deben seguir las indicaciones del profesional de salud.").font(.caption).foregroundStyle(MediVidaStyle.muted)
        }.navigationTitle("Acerca de")
    }
}

private struct EmptySurface: View {
    var text: String
    var body: some View {
        Surface {
            Text(text).font(.subheadline).foregroundStyle(MediVidaStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecordCard<Content: View>: View {
    var record: HealthRecord
    var accent: Color
    let content: Content
    init(record: HealthRecord, accent: Color, @ViewBuilder content: () -> Content) {
        self.record = record
        self.accent = accent
        self.content = content()
    }
    var body: some View {
        Surface {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title).font(.headline).foregroundStyle(MediVidaStyle.ink)
                if !record.detail.isEmpty && record.kind == .medicine {
                    Text(record.detail.split(separator: " ").first.map(String.init) ?? "")
                        .font(.caption.weight(.semibold)).foregroundStyle(accent)
                }
                Spacer()
                Image(systemName: record.kind.symbol).foregroundStyle(accent)
            }
            content
        }
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 4).padding(.vertical, 8) }
    }
}

private func kindColor(_ kind: RecordKind) -> Color {
    switch kind {
    case .medicine: MediVidaStyle.teal
    case .appointment: MediVidaStyle.green
    case .meal: MediVidaStyle.purple
    case .restriction: MediVidaStyle.orange
    }
}

private struct RecordEditorView: View {
    @EnvironmentObject private var store: MediVidaStore
    @Environment(\.dismiss) private var dismiss
    let kind: RecordKind
    let existing: HealthRecord?
    @State private var title: String
    @State private var detail: String
    @State private var place: String
    @State private var start: Date
    @State private var end: Date?
    @State private var times: [String]
    @State private var level: String
    @State private var foodItems: String
    @State private var hasStock: Bool
    @State private var stock: String
    @State private var unitsPerDose: String
    @State private var stockAlertAt: String
    @State private var reminderMinutes: Int
    @State private var dayBefore: Bool
    @State private var errorText: String?

    init(kind: RecordKind, existing: HealthRecord?) {
        self.kind = kind
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _detail = State(initialValue: existing?.detail ?? "")
        _place = State(initialValue: existing?.place ?? "")
        _start = State(initialValue: DateText.date(from: existing?.start ?? "") ?? .now)
        _end = State(initialValue: existing.flatMap { $0.end.isEmpty ? nil : DateText.date(from: $0.end) })
        _times = State(initialValue: ScheduleRules.times(existing?.times ?? "08:00"))
        _level = State(initialValue: existing?.level ?? FoodLevel.permitted.rawValue)
        _foodItems = State(initialValue: existing?.foodItems ?? "")
        _hasStock = State(initialValue: existing?.stockRemaining != nil)
        _stock = State(initialValue: existing?.stockRemaining.map(String.init) ?? "")
        _unitsPerDose = State(initialValue: String(existing?.unitsPerDose ?? 1))
        _stockAlertAt = State(initialValue: String(existing?.stockAlertAt ?? 5))
        _reminderMinutes = State(initialValue: existing?.reminderMinutes ?? 0)
        _dayBefore = State(initialValue: existing?.dayBefore ?? false)
    }

    var body: some View {
        Form {
            Section("Información") {
                TextField(kind == .restriction ? "Categoría" : "Nombre", text: $title)
                if kind != .restriction { TextField(kind == .appointment ? "Especialidad o motivo" : "Indicaciones", text: $detail, axis: .vertical).lineLimit(2...4) }
                if kind == .appointment { TextField("Lugar", text: $place) }
            }
            if kind == .restriction {
                Section("Clasificación") {
                    Picker("Estado", selection: $level) { ForEach(FoodLevel.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                    TextField("Alimentos (uno por línea)", text: $foodItems, axis: .vertical).lineLimit(3...8)
                }
            } else {
                Section("Horario") {
                    DatePicker("Fecha inicial", selection: $start, displayedComponents: .date)
                    Toggle("Tiene fecha final", isOn: Binding(get: { end != nil }, set: { end = $0 ? (end ?? start) : nil }))
                    if end != nil { DatePicker("Fecha final", selection: Binding(get: { end ?? start }, set: { end = $0 }), in: start..., displayedComponents: .date) }
                    ForEach(times.indices, id: \.self) { index in
                        HStack {
                            DatePicker("Hora \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                            if times.count > 1 { Button(role: .destructive) { times.remove(at: index) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Quitar hora") }
                        }
                    }
                    Button { times.append(DateText.timeString(from: .now)) } label: { Label("Agregar horario", systemImage: "plus") }
                }
                if kind == .medicine {
                    Section("Inventario") {
                        Toggle("Controlar existencias", isOn: $hasStock)
                        if hasStock {
                            TextField("Unidades disponibles", text: $stock).keyboardType(.numberPad)
                            TextField("Unidades por dosis", text: $unitsPerDose).keyboardType(.numberPad)
                            TextField("Avisarme cuando queden", text: $stockAlertAt).keyboardType(.numberPad)
                        }
                    }
                }
                if kind == .appointment {
                    Section("Recordatorio") {
                        Picker("Avisar con anticipación", selection: $reminderMinutes) {
                            Text("A la hora").tag(0); Text("15 minutos antes").tag(15); Text("30 minutos antes").tag(30)
                            Text("1 hora antes").tag(60); Text("1 día antes").tag(1440)
                        }
                        Toggle("También avisar el día anterior", isOn: $dayBefore)
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "Agregar \(kind.rawValue.lowercased())" : "Editar \(kind.rawValue.lowercased())")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.fontWeight(.semibold) }
        }
        .alert("Revisa la información", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(get: { DateText.time(times[index]) ?? .now }, set: { times[index] = DateText.timeString(from: $0) })
    }

    private func save() {
        var stockValue: Int?
        var unitsValue = existing?.unitsPerDose ?? 1
        var alertValue = existing?.stockAlertAt ?? 5
        var totalValue = existing?.stockTotal
        if kind == .medicine && hasStock {
            guard let parsedStock = Int(stock), (0...100_000).contains(parsedStock) else {
                errorText = "Las unidades disponibles deben ser un número entre 0 y 100 000."
                return
            }
            guard let parsedUnits = Int(unitsPerDose), (1...1000).contains(parsedUnits) else {
                errorText = "Las unidades por dosis deben ser un número entre 1 y 1 000."
                return
            }
            guard let parsedAlert = Int(stockAlertAt), (0...100_000).contains(parsedAlert) else {
                errorText = "El umbral de existencias debe ser un número entre 0 y 100 000."
                return
            }
            stockValue = parsedStock
            unitsValue = parsedUnits
            alertValue = parsedAlert
            totalValue = max(existing?.stockTotal ?? parsedStock, parsedStock)
        }
        let record = HealthRecord(
            id: existing?.id ?? UUID().uuidString,
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: detail,
            times: times.sorted().joined(separator: ","),
            start: DateText.string(from: start),
            end: end.map { DateText.string(from: $0) } ?? "",
            place: place,
            level: level,
            reminderMinutes: reminderMinutes,
            dayBefore: dayBefore,
            archived: false,
            stockRemaining: stockValue,
            unitsPerDose: unitsValue,
            stockAlertAt: alertValue,
            stockTotal: totalValue,
            foodItems: foodItems
        )
        do { try store.save(record); dismiss() }
        catch { errorText = error.localizedDescription }
    }
}

private struct ProfileEditorView: View {
    @EnvironmentObject private var store: MediVidaStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile = PatientProfile()
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Datos personales") {
                TextField("Nombre", text: $profile.name)
                TextField("Edad", text: $profile.age).keyboardType(.numberPad)
                TextField("Peso (kg)", text: $profile.weight).keyboardType(.decimalPad)
                TextField("Tipo de sangre", text: $profile.blood)
            }
            Section("Salud y contacto") {
                TextField("Alergias", text: $profile.allergies, axis: .vertical).lineLimit(2...5)
                TextField("Contacto de emergencia", text: $profile.contact)
                TextField("Teléfono", text: $profile.phone).keyboardType(.phonePad)
            }
        }
        .onAppear { profile = store.profile }
        .navigationTitle("Editar perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    do { try store.updateProfile(profile); dismiss() }
                    catch { errorText = error.localizedDescription }
                }
            }
        }
        .alert("Revisa la información", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }
}
