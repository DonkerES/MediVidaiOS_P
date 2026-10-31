import SwiftUI
import FirebaseAuth
import Network
import Combine

struct MediVidaAuthenticatedView: View {

    let user: User

    @EnvironmentObject private var auth: MediVidaAuthStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var store: MediVidaStore
    @StateObject private var networkMonitor = MediVidaNetworkMonitor()

    init(user: User) {
        self.user = user
        _store = StateObject(
            wrappedValue: MediVidaStore(ownerID: user.uid)
        )
    }

    var body: some View {
        MediVidaRootView()
            .environmentObject(store)
            .tint(MediVidaStyle.teal)
            .task {
                await store.syncFromCloud()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }

                Task {
                    await store.syncFromCloud()
                }
            }
            .onChange(of: networkMonitor.isConnected) {
                oldValue, newValue in

                // Reintentar únicamente al pasar de desconectado
                // a conectado. La sincronización inicial se mantiene
                // en el modificador .task existente.
                guard oldValue == false && newValue == true else {
                    return
                }

                Task {
                    await store.syncFromCloud()
                }
            }
            .alert(
                "MediVida",
                isPresented: Binding(
                    get: { auth.message != nil },
                    set: { if !$0 { auth.message = nil } }
                )
            ) {
                Button("Aceptar", role: .cancel) {
                    auth.message = nil
                }
            } message: {
                Text(auth.message ?? "")
            }
    }
}


@MainActor
final class MediVidaNetworkMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "com.example.medivida.network-monitor"
    )

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied

            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
