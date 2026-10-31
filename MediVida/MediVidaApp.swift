import SwiftUI
import Combine
import FirebaseAuth

@main
struct MediVidaApp: App {

    @UIApplicationDelegateAdaptor(MediVidaAppDelegate.self)
    private var appDelegate

    @StateObject private var auth = MediVidaAuthStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isCheckingSession {
                    ProgressView("Cargando MediVida…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else if let user = auth.user {
                    MediVidaAuthenticatedView(user: user)
                        .id(user.uid)

                } else {
                    MediVidaAuthView()
                }
            }
            .environmentObject(auth)
            .tint(MediVidaStyle.teal)
        }
    }
}
