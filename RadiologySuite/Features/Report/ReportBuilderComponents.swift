import SwiftUI
import UIKit

// MARK: - Clinic Letterhead

/// Data-driven letterhead banner rendered from the stored `ClinicProfile` with
/// seamless fallback to User Defaults / Settings profile (`user.name`, `user.hospital`).
struct ReportLetterhead: View {
    let clinic: ClinicProfile?

    @AppStorage("user.name") private var storedDoctorName = ""
    @AppStorage("user.hospital") private var storedHospitalName = ""

    private var effectiveClinicName: String {
        if let name = clinic?.clinicName, !name.isEmpty { return name }
        return storedHospitalName.isEmpty ? "Imaging & Diagnostic Center" : storedHospitalName
    }

    private var effectiveDoctorName: String {
        if let name = clinic?.doctorName, !name.isEmpty { return name }
        if storedDoctorName.isEmpty { return "Dr. Sourav Gupta" }
        return storedDoctorName.hasPrefix("Dr.") ? storedDoctorName : "Dr. \(storedDoctorName)"
    }

    private var effectiveTagline: String {
        if let tag = clinic?.tagline, !tag.isEmpty { return tag }
        return "Digital Radiology & Diagnostic Consultation"
    }

    private var accent: Color {
        guard let hex = clinic?.themeColorHex, !hex.isEmpty else { return DS.coral }
        return Color(hex: hex)
    }

    var body: some View {
        Tile {
            HStack(spacing: 14) {
                if let data = clinic?.logoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.coral.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(DS.coral)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(effectiveClinicName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                        .lineLimit(2)
                    Text(effectiveTagline)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.subAdaptive)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(effectiveDoctorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.inkAdaptive)
                        .lineLimit(2)
                    Text(credentials)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.subAdaptive)
                        .lineLimit(2)
                }
            }
        }
    }

    private var credentials: String {
        let list = [clinic?.doctorQualifications, clinic?.doctorRegNumber]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if list.isEmpty {
            return "Consultant Radiologist"
        }
        return list.joined(separator: " · ")
    }
}

// MARK: - Demographics & Encounter Bar

struct ReportDemographicsBar: View {
    @Bindable var report: RadiologyReport

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 16) {
                // Patient identity grid
                HStack(alignment: .top, spacing: 0) {
                    demoField("PATIENT", value: patientName)
                    Spacer()
                    demoField("MRN / ARR", value: referenceNumber, monospaced: true, accent: true)
                    Spacer()
                    demoField("AGE / SEX", value: ageSex)
                    Spacer()
                    demoField("STUDY DATE", value: report.studyDate.formatted(date: .abbreviated, time: .omitted))
                }

                Divider()

                // Modality selector (driven by shared catalog)
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("MODALITY")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ImagingModality.allCases) { modality in
                                Button {
                                    DS.haptic(.light)
                                    report.modality = modality.rawValue
                                } label: {
                                    Label(modality.rawValue, systemImage: modality.symbol)
                                        .font(.system(size: 12, weight: selected(modality) ? .bold : .medium))
                                        .foregroundStyle(selected(modality) ? .white : DS.inkAdaptive)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule().fill(selected(modality) ? DS.coral : Color.gray.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Priority
                HStack {
                    fieldLabel("PRIORITY")
                    Spacer()
                    Picker("Priority", selection: $report.priority) {
                        Text("Routine").tag(ReportPriority.routine)
                        Text("Urgent").tag(ReportPriority.urgent)
                        Text("STAT").tag(ReportPriority.stat)
                    }
                    .pickerStyle(.menu)
                    .tint(priorityColor)
                }
            }
        }
    }

    private func selected(_ modality: ImagingModality) -> Bool {
        report.modality == modality.rawValue
    }

    private var priorityColor: Color {
        switch report.priority {
        case .stat: return .red
        case .urgent: return .orange
        case .routine: return DS.inkAdaptive
        }
    }

    private var patientName: String {
        report.patient?.name ?? report.patientName ?? ""
    }

    private var referenceNumber: String {
        if let arr = report.patient?.arrNumber, !arr.isEmpty { return arr }
        if let mrn = report.patient?.mrn, !mrn.isEmpty { return mrn }
        return report.accessionNumber
    }

    private var ageSex: String {
        let sex = report.patient?.sex ?? ""
        let age = report.patient?.age ?? 0
        if age > 0 { return "\(age)y / \(sex)" }
        return sex.isEmpty ? "—" : sex
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(DS.subAdaptive)
    }

    private func demoField(_ label: String, value: String, monospaced: Bool = false, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            fieldLabel(label)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13, weight: accent ? .semibold : .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(accent ? DS.coral : DS.inkAdaptive)
                .lineLimit(2)
        }
    }
}

// MARK: - Section Editor

struct ReportSectionEditor: View {
    let section: ReportSection
    @Binding var text: String
    var onPolish: () -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(section.heading)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                        .textCase(nil)
                        .lineLimit(1)

                    if let badge = blockBadge {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(DS.coral.opacity(0.12)))
                            .foregroundStyle(DS.coral)
                    }

                    Spacer()

                    Button(action: onPolish) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.coral)
                    }
                    .buttonStyle(.plain)

                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.subAdaptive)
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 14.5))
                    .foregroundStyle(DS.inkAdaptive)
                    .lineSpacing(4)
                    .padding(12)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.lineAdaptive, lineWidth: 1)
                    )
            }
        }
    }

    private var blockBadge: String? {
        switch section.blockType {
        case "vitalsGrid": return "VITALS"
        case "checkbox": return "CHECKBOX"
        case "pencilKitDrawing": return "DRAWING"
        default: return nil
        }
    }
}

// MARK: - Signature & Status Footer

struct ReportSignatureFooter: View {
    let report: RadiologyReport
    let clinic: ClinicProfile?

    @AppStorage("user.name") private var storedDoctorName = ""

    private var effectiveDoctorName: String {
        if let name = clinic?.doctorName, !name.isEmpty { return name }
        if storedDoctorName.isEmpty { return "Dr. Sourav Gupta" }
        return storedDoctorName.hasPrefix("Dr.") ? storedDoctorName : "Dr. \(storedDoctorName)"
    }

    var body: some View {
        Tile {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    fieldLabel("REPORT STATUS")
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(effectiveDoctorName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                        .lineLimit(1)
                    Text(clinic?.doctorQualifications.isEmpty == false ? clinic!.doctorQualifications : "Consultant Radiologist")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.subAdaptive)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusText: String {
        switch report.status {
        case .signed: return "Signed & Verified"
        case .amended: return "Amended"
        case .draft: return "Draft — pending signature"
        }
    }

    private var statusColor: Color {
        switch report.status {
        case .signed: return .green
        case .amended: return .orange
        case .draft: return DS.subAdaptive
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(DS.subAdaptive)
    }
}

// MARK: - Bottom Action Dock

struct ReportActionBar: View {
    var isBusy: Bool = false
    var onAutoFormat: () -> Void
    var onWhatsApp: () -> Void
    var onExport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton("AI Auto-Format", systemImage: "wand.and.stars", style: .secondary, busy: isBusy, action: onAutoFormat)
            actionButton("WhatsApp", systemImage: "paperplane.fill", style: .whatsApp, action: onWhatsApp)
            actionButton("Export PDF", systemImage: "doc.fill", style: .primary, action: onExport)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private enum ActionStyle {
        case primary, secondary, whatsApp
    }

    private func actionButton(_ title: String, systemImage: String, style: ActionStyle, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(style == .primary ? .white : DS.inkAdaptive)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
            }
            .foregroundStyle(style == .primary ? .white : DS.inkAdaptive)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(background(for: style))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func background(for style: ActionStyle) -> some View {
        switch style {
        case .primary:
            Capsule().fill(DS.coral).shadow(color: DS.coral.opacity(0.4), radius: 10, y: 4)
        case .whatsApp:
            Capsule().fill(Color(hex: "#25D366")).shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        case .secondary:
            Capsule().fill(DS.card).shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
    }
}
