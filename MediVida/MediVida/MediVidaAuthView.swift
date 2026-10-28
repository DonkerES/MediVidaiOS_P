import SwiftUI
import UIKit

struct MediVidaAuthView: View {

    @EnvironmentObject private var auth: MediVidaAuthStore

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 10) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(MediVidaStyle.teal)

                            Text("MediVida")
                                .font(.largeTitle.bold())

                            Text(
                                isRegistering
                                ? "Crea tu cuenta para comenzar."
                                : "Tu salud, organizada en un solo lugar."
                            )
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)

                        VStack(spacing: 16) {
                            if isRegistering {
                                TextField("Nombre completo", text: $name)
                                    .textContentType(.name)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                    .textFieldStyle(.roundedBorder)
                            }

                            TextField(
                                "Correo electrónico",
                                text: $email
                            )
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                            SecureField(
                                "Contraseña",
                                text: $password
                            )
                            .textContentType(
                                isRegistering ? .newPassword : .password
                            )
                            .textFieldStyle(.roundedBorder)

                            Button {
                                Task {
                                    isBusy = true

                                    if isRegistering {
                                        await auth.register(
                                            name: name,
                                            email: email,
                                            password: password
                                        )
                                    } else {
                                        await auth.signIn(
                                            email: email,
                                            password: password
                                        )
                                    }

                                    isBusy = false
                                }
                            } label: {
                                Group {
                                    if isBusy {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(
                                            isRegistering
                                            ? "Crear cuenta"
                                            : "Iniciar sesión"
                                        )
                                        .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    MediVidaStyle.teal,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .foregroundStyle(.white)
                            }
                            .disabled(isBusy)

                            if !isRegistering {
                                Button("¿Olvidaste tu contraseña?") {
                                    Task {
                                        isBusy = true
                                        await auth.resetPassword(email: email)
                                        isBusy = false
                                    }
                                }
                                .disabled(isBusy)
                                .frame(maxWidth: .infinity)
                            }
                        }

                        Button {
                            auth.message = nil

                            withAnimation {
                                isRegistering.toggle()
                            }
                        } label: {
                            Text(
                                isRegistering
                                ? "¿Ya tienes una cuenta? Inicia sesión"
                                : "¿Eres nuevo? Crea una cuenta"
                            )
                            .font(.subheadline.weight(.medium))
                        }
                        .disabled(isBusy)

                        Text("Tus datos de salud se guardan en este dispositivo y se sincronizan con Firebase cuando hay conexión.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationBarHidden(true)
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
