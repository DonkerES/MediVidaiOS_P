import Foundation

/// Valida y normaliza los datos del perfil antes de guardarlos.
public enum ProfileRules {

    /// Devuelve un perfil validado cuyo nombre no tiene espacios exteriores.
    public static func validated(
        _ profile: PatientProfile
    ) throws -> PatientProfile {
        let cleanName = profile.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard (2...100).contains(cleanName.count) else {
            throw RuleError("Escribe un nombre de 2 a 100 caracteres.")
        }

        guard profile.age.count <= 3 else {
            throw RuleError("La edad no puede superar 3 caracteres.")
        }

        if !profile.age.isEmpty,
           !(Int(profile.age).map { (0...130).contains($0) } ?? false) {
            throw RuleError("La edad debe ser un número entre 0 y 130.")
        }

        guard profile.weight.count <= 6 else {
            throw RuleError("El peso no puede superar 6 caracteres.")
        }

        if !profile.weight.isEmpty,
           !(Double(profile.weight).map { (0.1...500).contains($0) } ?? false) {
            throw RuleError("El peso debe estar entre 0,1 y 500 kg.")
        }

        let allowedBloodGroups: Set<String> = [
            "", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"
        ]

        guard allowedBloodGroups.contains(profile.blood) else {
            throw RuleError("Selecciona un grupo sanguíneo válido.")
        }

        guard profile.allergies.count <= 1000 else {
            throw RuleError("Las alergias no pueden superar 1000 caracteres.")
        }

        guard profile.contact.count <= 100 else {
            throw RuleError("El contacto no puede superar 100 caracteres.")
        }

        guard profile.phone.count <= 30 else {
            throw RuleError("El teléfono no puede superar 30 caracteres.")
        }

        return PatientProfile(
            name: cleanName,
            age: profile.age,
            weight: profile.weight,
            blood: profile.blood,
            allergies: profile.allergies,
            contact: profile.contact,
            phone: profile.phone,
            notifications: profile.notifications
        )
    }
}
