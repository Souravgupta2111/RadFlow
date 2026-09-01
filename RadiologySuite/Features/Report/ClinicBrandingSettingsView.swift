import SwiftUI
import SwiftData
import PhotosUI

/// "Canva for Medical Reports" — Clinic Branding & Header Designer.
/// Enables clinics to fully customize their letterhead, logo, typography colors,
/// doctor signatures, and contact details with instant live visual preview.
struct ClinicBrandingSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [ClinicProfile]
    
    @State private var clinicName: String = "Metro Imaging & Diagnostic Center"
    @State private var tagline: String = "Advanced Multi-Slice CT & MRI Scanning"
    @State private var address: String = "104 Healthcare Boulevard, Medical Enclave"
    @State private var cityStateZip: String = "New Delhi, DL 110029"
    @State private var phone: String = "+91 (011) 4567-8900"
    @State private var email: String = "reports@metroimaging.org"
    @State private var website: String = "www.metroimaging.org"
    @State private var doctorName: String = "Dr. Rajesh Sharma, MD"
    @State private var doctorQualifications: String = "MD (Radiodiagnosis), FRCR"
    @State private var doctorRegNumber: String = "DMC-84920"
    @State private var selectedThemeHex: String = "#0A84FF"
    @State private var templateStyle: String = "modern"
    
    @State private var logoItem: PhotosPickerItem? = nil
    @State private var logoData: Data? = nil
    
    @State private var signatureItem: PhotosPickerItem? = nil
    @State private var signatureData: Data? = nil

    let themeColors = [
        ("#0A84FF", "Azure Blue"),
        ("#10B981", "Emerald Green"),
        ("#6366F1", "Indigo Modern"),
        ("#E11D48", "Ruby Crimson"),
        ("#0F172A", "Slate Luxury")
    ]

    let styles = [
        ("modern", "Modern"),
        ("classic", "Classic"),
        ("minimal", "Minimalist")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Live Canva-style Letterhead Preview Card
                liveLetterheadPreview
                
                // Style & Color Palette Selector
                styleAndColorSection
                
                // Clinic Details Form
                clinicDetailsSection
                
                // Doctor & Signatures
                doctorAndSignatureSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .navigationTitle("Clinic Branding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProfile()
                    dismiss()
                }
                .fontWeight(.bold)
                .tint(DS.coral)
            }
        }
        .onAppear {
            loadExistingProfile()
        }
    }

    // MARK: - Live Canva Letterhead Preview
    private var liveLetterheadPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if let data = logoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: selectedThemeHex).opacity(0.15))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "cross.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(hex: selectedThemeHex))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(clinicName.isEmpty ? "CLINIC NAME" : clinicName.uppercased())
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color(hex: selectedThemeHex))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    Text(tagline.isEmpty ? "Diagnostic & Imaging Services" : tagline)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.subAdaptive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    
                    Text("\(address), \(cityStateZip)")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.subAdaptive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(phone)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.inkAdaptive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(email)
                        .font(.system(size: 8))
                        .foregroundStyle(DS.subAdaptive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .padding(14)
            .background(Color.white)
            
            // Canva-style accent divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: selectedThemeHex), Color(hex: selectedThemeHex).opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)
            
            // Preview Sample Report Text
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PATIENT: Ramesh Iyer (45y / M)")
                        .font(.system(size: 9, weight: .bold))
                    Spacer()
                    Text("ACCESSION: ACC-9482")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(DS.inkAdaptive.opacity(0.8))
                
                Text("FINDINGS: Heart size is normal. Bilateral lung fields are clear. No focal consolidation or pleural effusion.")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.subAdaptive)
                    .lineLimit(2)
                
                Divider().padding(.vertical, 2)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        if let data = signatureData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 20)
                        } else {
                            Text("Rajesh Sharma")
                                .font(.custom("Snell Roundhand", size: 14))
                                .foregroundStyle(Color(hex: selectedThemeHex))
                        }
                        Text(doctorName)
                            .font(.system(size: 8, weight: .bold))
                        Text("Reg: \(doctorRegNumber)")
                            .font(.system(size: 7))
                            .foregroundStyle(DS.subAdaptive)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.85))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - Style & Color Palette
    private var styleAndColorSection: some View {
        Tile {
            VStack(alignment: .leading, spacing: 14) {
                Text("Template Style & Accent Color")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.inkAdaptive)
                
                // Color circles
                HStack(spacing: 16) {
                    ForEach(themeColors, id: \.0) { hex, name in
                        Button {
                            DS.haptic(.light)
                            selectedThemeHex = hex
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 36, height: 36)
                                
                                if selectedThemeHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Style Picker
                Picker("Layout Style", selection: $templateStyle) {
                    ForEach(styles, id: \.0) { key, label in
                        Text(label).tag(key)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Clinic Details Form
    private var clinicDetailsSection: some View {
        Tile {
            VStack(alignment: .leading, spacing: 12) {
                Text("Clinic Information")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.inkAdaptive)
                
                PhotosPicker(selection: $logoItem, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text(logoData == nil ? "Upload Clinic Logo" : "Change Clinic Logo")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: selectedThemeHex))
                    .padding(.vertical, 4)
                }
                .onChange(of: logoItem) { _ in
                    Task {
                        if let data = try? await logoItem?.loadTransferable(type: Data.self) {
                            self.logoData = data
                        }
                    }
                }

                CustomField(title: "Clinic Name", text: $clinicName)
                CustomField(title: "Tagline / Sub-header", text: $tagline)
                CustomField(title: "Street Address", text: $address)
                CustomField(title: "City, State, PIN/ZIP", text: $cityStateZip)
                CustomField(title: "Phone / WhatsApp", text: $phone)
                CustomField(title: "Email", text: $email)
                CustomField(title: "Website", text: $website)
            }
        }
    }

    // MARK: - Doctor & Signatures
    private var doctorAndSignatureSection: some View {
        Tile {
            VStack(alignment: .leading, spacing: 12) {
                Text("Radiologist Credentials & Signature")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.inkAdaptive)

                PhotosPicker(selection: $signatureItem, matching: .images) {
                    HStack {
                        Image(systemName: "signature")
                        Text(signatureData == nil ? "Upload Digital Signature" : "Change Digital Signature")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: selectedThemeHex))
                    .padding(.vertical, 4)
                }
                .onChange(of: signatureItem) { _ in
                    Task {
                        if let data = try? await signatureItem?.loadTransferable(type: Data.self) {
                            self.signatureData = data
                        }
                    }
                }

                CustomField(title: "Radiologist Name", text: $doctorName)
                CustomField(title: "Degrees / Qualifications", text: $doctorQualifications)
                CustomField(title: "Medical Registration #", text: $doctorRegNumber)
            }
        }
    }

    private func loadExistingProfile() {
        if let existing = profiles.first(where: { $0.isDefault }) ?? profiles.first {
            clinicName = existing.clinicName
            tagline = existing.tagline
            address = existing.address
            cityStateZip = existing.cityStateZip
            phone = existing.phone
            email = existing.email
            website = existing.website
            doctorName = existing.doctorName
            doctorQualifications = existing.doctorQualifications
            doctorRegNumber = existing.doctorRegNumber
            selectedThemeHex = existing.themeColorHex
            templateStyle = existing.templateStyle
            logoData = existing.logoData
            signatureData = existing.signatureData
        }
    }

    private func saveProfile() {
        DS.haptic(.medium)
        if let existing = profiles.first(where: { $0.isDefault }) ?? profiles.first {
            existing.clinicName = clinicName
            existing.tagline = tagline
            existing.address = address
            existing.cityStateZip = cityStateZip
            existing.phone = phone
            existing.email = email
            existing.website = website
            existing.doctorName = doctorName
            existing.doctorQualifications = doctorQualifications
            existing.doctorRegNumber = doctorRegNumber
            existing.themeColorHex = selectedThemeHex
            existing.templateStyle = templateStyle
            existing.logoData = logoData
            existing.signatureData = signatureData
        } else {
            let profile = ClinicProfile(
                clinicName: clinicName,
                tagline: tagline,
                address: address,
                cityStateZip: cityStateZip,
                phone: phone,
                email: email,
                website: website,
                doctorName: doctorName,
                doctorQualifications: doctorQualifications,
                doctorRegNumber: doctorRegNumber,
                logoData: logoData,
                signatureData: signatureData,
                themeColorHex: selectedThemeHex,
                templateStyle: templateStyle,
                isDefault: true
            )
            context.insert(profile)
        }
        try? context.save()
    }
}

private struct CustomField: View {
    let title: String
    @Binding var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.subAdaptive)
            TextField(title, text: $text)
                .font(.system(size: 14))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(DS.paperAdaptive))
        }
    }
}
