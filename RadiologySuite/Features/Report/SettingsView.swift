import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("user.name") private var userName = ""
    @AppStorage("user.credentials") private var userCredentials = ""
    @AppStorage("user.hospital") private var hospitalName = ""
    @AppStorage("user.department") private var departmentName = ""

    @AppStorage("report.defaultModality") private var defaultModality = "XR"
    @AppStorage("export.defaultFormat") private var defaultFormat = "PDF"
    @AppStorage("export.includeDisclaimer") private var includeDisclaimer = true

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("ui.themeMode") private var themeMode = 0 // 0=System, 1=Light, 2=Dark
    
    @ObservedObject private var auth = AuthService.shared
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DS.subAdaptive)
                            .padding(.trailing, 4)
                    }
                    Text("Settings")
                        .font(DS.display(44))
                        .tracking(-1.6)
                        .foregroundStyle(DS.inkAdaptive)
                    Spacer()
                }

                // MARK: - Profile
                Tile {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(userName.isEmpty ? "Dr." : userName)
                                    .font(DS.h2)
                                    .foregroundStyle(DS.inkAdaptive)
                                Text(hospitalName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.subAdaptive)
                            }
                            Spacer()
                            Image(systemName: "applelogo")
                                .font(.system(size: 24))
                                .foregroundStyle(DS.inkAdaptive)
                        }

                        Divider()

                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(DS.coral)
                            Text("Signed in with Apple")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.subAdaptive)
                            Spacer()
                            if let email = UserDefaults.standard.string(forKey: "user.appleEmail") {
                                Text(email)
                                    .font(.system(size: 13))
                                    .foregroundStyle(DS.inkAdaptive)
                            }
                        }
                    }
                }

                // MARK: - Identity
                Tile {
                    VStack(alignment: .leading, spacing: 12) {
                        label("EDIT IDENTITY")
                        SettingsTextField(placeholder: "Radiologist name", text: $userName)
                        SettingsTextField(placeholder: "Credentials (e.g. MD, FRCR)", text: $userCredentials)
                        SettingsTextField(placeholder: "Hospital name", text: $hospitalName)
                        SettingsTextField(placeholder: "Department", text: $departmentName)
                    }
                }

                // MARK: - Report Templates
                Tile {
                    VStack(alignment: .leading, spacing: 12) {
                        label("REPORT TEMPLATES")
                        NavigationLink(destination: TemplatesListView()) {
                            HStack {
                                Text("Manage Templates").font(DS.bodyFont).foregroundStyle(DS.inkAdaptive)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.subAdaptive)
                            }
                        }
                    }
                }

                // MARK: - Report Defaults
                Tile {
                    VStack(alignment: .leading, spacing: 12) {
                        label("REPORT DEFAULTS")
                        SettingsPicker(label: "Default modality", selection: $defaultModality, options: ImagingModality.allCases.map(\.rawValue))
                        SettingsPicker(label: "Export format", selection: $defaultFormat, options: ["PDF", "Plain text", "Both"])
                    }
                }

                // MARK: - Appearance
                Tile {
                    VStack(alignment: .leading, spacing: 10) {
                        label("APPEARANCE")
                        Toggle("Dark Mode", isOn: Binding(
                            get: { themeMode == 0 ? colorScheme == .dark : themeMode == 2 },
                            set: { themeMode = $0 ? 2 : 1 }
                        )).font(DS.bodyFont)
                    }
                }

                // MARK: - Legal & Medical Disclaimer
                Tile {
                    VStack(alignment: .leading, spacing: 12) {
                        label("LEGAL")

                        NavigationLink(destination: LegalView(page: .privacy)) {
                            settingsRow(icon: "lock.shield", title: "Privacy Policy")
                        }

                        NavigationLink(destination: LegalView(page: .terms)) {
                            settingsRow(icon: "doc.text", title: "Terms & Conditions")
                        }

                        Divider()

                        // Medical Disclaimer (Guideline 1.4.1)
                        Text("Radflow is a dictation & reporting productivity tool. It is not a medical device and is not intended for clinical diagnosis without a medical expert.")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.subAdaptive)
                    }
                }

                // MARK: - Account Actions
                Tile {
                    VStack(alignment: .leading, spacing: 12) {
                        label("ACCOUNT")
                        
                        Button {
                            auth.signOut()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(DS.subAdaptive)
                                Text("Sign Out").font(DS.bodyFont).foregroundStyle(DS.inkAdaptive)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                Text("Delete Account").font(DS.bodyFont).foregroundStyle(.red)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Version info
                HStack {
                    Spacer()
                    Text("Radflow v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.subAdaptive)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task {
                    let ok = await auth.deleteAccount()
                    if ok { 
                        dismiss() 
                    }
                }
            }
        } message: {
            Text("This will permanently delete your account and all data from our servers. This action cannot be undone.")
        }
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(DS.coralDeep)
    }

    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.subAdaptive)
            Text(title).font(DS.bodyFont).foregroundStyle(DS.inkAdaptive)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.subAdaptive)
        }
    }
}

struct SettingsTextField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(DS.bodyFont)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(DS.paperAdaptive))
    }
}

struct SettingsPicker: View {
    var label: String
    @Binding var selection: String
    var options: [String]

    var body: some View {
        HStack {
            Text(label).font(DS.bodyFont)
            Spacer()
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.coral)
        }
    }
}
