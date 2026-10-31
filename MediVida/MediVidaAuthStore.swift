import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UserNotifications

private enum MediVidaProfileRecoveryError: LocalizedError {
    case incompleteProfile

    var errorDescription: String? {
        "El perfil existe, pero faltan campos requeridos. "
            + "No se modificó el documento existente."
    }
}

@MainActor
final class MediVidaAuthStore: ObservableObject {

    @Published private(set) var user: User?
    @Published private(set) var isCheckingSession = true
    @Published var message: String?

    private var listener: AuthStateDidChangeListenerHandle?
    private var isResolvingAuthentication = false

    init() {
        Auth.auth().languageCode = "es"

        listener = Auth.auth().addStateDidChangeListener {
            [weak self] _, authUser in

            let isSignedIn = authUser != nil

            Task { @MainActor [weak self] in
                guard let self else { return }

                // Durante el registro, register() controla cuándo
                // se publica el usuario autenticado.
                guard !self.isResolvingAuthentication else { return }

                self.user = isSignedIn ? Auth.auth().currentUser : nil
                self.isCheckingSession = false
            }
        }
    }

    func signIn(email: String, password: String) async {
        message = nil

        let cleanEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanEmail.isEmpty, !password.isEmpty else {
            message = "Escribe tu correo electrónico y contraseña."
            return
        }

        isResolvingAuthentication = true

        defer {
            isResolvingAuthentication = false
            isCheckingSession = false
        }

        do {
            let result = try await Auth.auth().signIn(
                withEmail: cleanEmail,
                password: password
            )

            do {
                try await ensureProfileExists(for: result.user)
            } catch {
                message = "Iniciaste sesión, pero no pudimos comprobar "
                    + "o recuperar tu perfil en Firebase. "
                    + "No se sobrescribieron los datos existentes. "
                    + "Comprueba la conexión y los permisos de Firestore. "
                    + "Detalle: " + error.localizedDescription
            }

            user = result.user

        } catch {
            user = nil
            message = error.localizedDescription
        }
    }

    func register(
        name: String,
        email: String,
        password: String
    ) async {
        message = nil

        let cleanName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let cleanEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard (2...100).contains(cleanName.count) else {
            message = "El nombre debe tener entre 2 y 100 caracteres."
            return
        }

        guard !cleanEmail.isEmpty else {
            message = "Escribe tu correo electrónico."
            return
        }

        guard password.count >= 6 else {
            message = "La contraseña debe tener al menos 6 caracteres."
            return
        }

        isResolvingAuthentication = true

        defer {
            isResolvingAuthentication = false
            isCheckingSession = false
        }

        var accountCreated = false

        do {
            let result = try await Auth.auth().createUser(
                withEmail: cleanEmail,
                password: password
            )

            accountCreated = true
            let uid = result.user.uid

            // Completar el nombre de la cuenta antes de publicar
            // el usuario en el estado de la aplicación.
            do {
                let profileChange =
                    result.user.createProfileChangeRequest()

                profileChange.displayName = cleanName
                try await profileChange.commitChanges()
            }

            let profileData: [String: Any] = [
                "name": cleanName,
                "age": "",
                "weight": "",
                "blood": "",
                "allergies": "",
                "contact": "",
                "phone": "",
                "notifications": true
            ]

            do {
                try await Firestore.firestore()
                    .collection("users")
                    .document(uid)
                    .setData(profileData)
            } catch {
                try? Auth.auth().signOut()
                user = nil

                message = """
                La cuenta se creó, pero no se pudo guardar el perfil \
                inicial en Firebase. Comprueba las reglas de Firestore \
                y la conexión antes de iniciar sesión.
                """
                return
            }

            // Enviar la verificación antes de publicar al usuario.
            // Después de esta llamada no volveremos a utilizar result.user.
            do {
                try await result.user.sendEmailVerification()

                message = """
                Cuenta creada correctamente. Te enviamos un correo \
                para verificar tu dirección.
                """
            } catch {
                message = """
                Tu cuenta fue creada y el perfil está guardado, pero \
                no pudimos enviar el correo de verificación. \
                Comprueba tu conexión.
                """
            }

            // El perfil inicial ya está en Firestore y terminó
            // la operación del correo; ahora se publica la sesión.
            user = Auth.auth().currentUser

        } catch {
            if accountCreated {
                try? Auth.auth().signOut()
                user = nil
            }

            message = error.localizedDescription
        }
    }

    private func ensureProfileExists(for user: User) async throws {
        let reference = Firestore.firestore()
            .collection("users")
            .document(user.uid)

        let snapshot = try await reference.getDocument()

        if snapshot.exists {
            guard
                let data = snapshot.data(),
                data["name"] as? String != nil,
                data["age"] as? String != nil,
                data["weight"] as? String != nil,
                data["blood"] as? String != nil,
                data["allergies"] as? String != nil,
                data["contact"] as? String != nil,
                data["phone"] as? String != nil,
                data["notifications"] as? Bool != nil
            else {
                throw MediVidaProfileRecoveryError.incompleteProfile
            }

            // No sobrescribir perfiles existentes.
            return
        }

        let displayName = user.displayName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""

        let emailName = user.email?
            .split(separator: "@")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let candidate = (2...100).contains(displayName.count)
            ? displayName
            : emailName

        let initialName = (2...100).contains(candidate.count)
            ? candidate
            : "Usuario MediVida"

        let profileData: [String: Any] = [
            "name": initialName,
            "age": "",
            "weight": "",
            "blood": "",
            "allergies": "",
            "contact": "",
            "phone": "",
            "notifications": true
        ]

        try await reference.setData(profileData)
    }

    func resetPassword(email: String) async {
        message = nil

        let cleanEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanEmail.isEmpty else {
            message = "Escribe tu correo para recuperar la contraseña."
            return
        }

        do {
            try await Auth.auth().sendPasswordReset(
                withEmail: cleanEmail
            )

            message = """
            Si el correo corresponde a una cuenta registrada, \
            recibirás las instrucciones para restablecer la contraseña.
            """
        } catch {
            message = error.localizedDescription
        }
    }

    func signOut() async {
        let center = UNUserNotificationCenter.current()

        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix("medivida_") }

        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: identifiers
            )

            center.removeDeliveredNotifications(
                withIdentifiers: identifiers
            )
        }

        do {
            try Auth.auth().signOut()
        } catch {
            message = error.localizedDescription
        }
    }
}
