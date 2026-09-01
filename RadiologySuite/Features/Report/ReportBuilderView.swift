import SwiftUI
import SwiftData

/// Modular, data-driven report editor.
/// Compose letterhead, demographics, section editors, signature footer and a
/// floating action bar. All display values come from `RadiologyReport`,
/// `ClinicProfile` and the shared `ImagingModality` catalog — nothing is
/// hard-coded in the view.
struct ReportBuilderView: View {
    @Bindable var report: RadiologyReport
    @Query private var clinicProfiles: [ClinicProfile]
    @Query(sort: \ReportTemplate.name) private var allTemplates: [ReportTemplate]

    @State private var llm: LLMService = LLMProvider.service
    @State private var isAutoFilling = false
    @State private var showSignConfirm = false
    @State private var showAddSection = false
    @State private var newSectionHeading = ""
    @State private var showPatientSelector = false

    private var clinic: ClinicProfile? {
        clinicProfiles.first(where: { $0.isDefault }) ?? clinicProfiles.first
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    patientSelectorBlock
                    sectionsBlock
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                // Add padding so scroll content clears the floating bar
                .padding(.bottom, 120)
            }
            .background(DS.paperAdaptive.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                floatingActionBar
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    signReport()
                    dismiss()
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.coral)
            }
        }
        .alert("Add Section", isPresented: $showAddSection) {
            TextField("Section heading", text: $newSectionHeading)
            Button("Add") { commitNewSection() }
            Button("Cancel", role: .cancel) { newSectionHeading = "" }
        }
        .sheet(isPresented: $showPatientSelector) {
            PatientSelectionSheet(report: report)
                .modelContext(context)
        }
        .onAppear { ReportOpenState.shared.isReportOpen = true }
        .onDisappear { ReportOpenState.shared.isReportOpen = false }
    }
    
    private var floatingActionBar: some View {
        HStack(spacing: 16) {
            Button(action: printReport) {
                Image(systemName: "printer.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.black.opacity(0.8)))
            }
            
            Button(action: sendWhatsApp) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                    Text("WhatsApp")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.green))
            }
            
            ShareLink(item: generateShareText()) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(DS.coral))
            }
        }
        .padding(10)
        .background(
            Capsule()
                .fill(DS.card)
                .shadow(color: Color.black.opacity(0.15), radius: 15, y: 8)
        )
        .padding(.bottom, 24)
    }

    private var navigationTitle: String {
        if let modality = ImagingModality(rawValue: report.modality) {
            return "\(modality.displayName) Report"
        }
        return report.modality.isEmpty ? "Report" : "\(report.modality) Report"
    }

    private var patientSelectorBlock: some View {
        Button {
            showPatientSelector = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.coral)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Patient")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(DS.subAdaptive)
                        .textCase(.uppercase)

                    if let p = report.patient {
                        Text(p.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.inkAdaptive)
                            .lineLimit(1)
                        Text("\(p.age)y · \(p.sex) · \(p.phone.isEmpty ? "No phone" : p.phone)")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.subAdaptive)
                            .lineLimit(1)
                    } else if let detected = report.patientName, !detected.isEmpty {
                        Text(detected)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.inkAdaptive)
                            .lineLimit(1)
                        Text("Tap to link this patient")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.subAdaptive)
                    } else {
                        Text("Tap to select or add patient")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.inkAdaptive)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.subAdaptive)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var sectionsBlock: some View {
        Group {
            if let t = report.template, !t.blocks.isEmpty {
                templateCanvas(t)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($report.sections) { $section in
                        ReportSectionEditor(
                            section: section,
                            text: $section.text,
                            onPolish: { polishSection(section: section) },
                            onDelete: { deleteSection(section.id) }
                        )
                    }
                }
            }
        }
    }

    private func templateCanvas(_ t: ReportTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Document Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.headerTitle)
                        .font(.custom(fontFamilyName(t), size: 24).weight(.heavy))
                        .foregroundStyle(Color(hex: t.accentColorHex))
                        .tracking(0.5)
                    Text(t.subtitle)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DS.subAdaptive)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DATE: \(report.studyDate.formatted(.dateTime.month().day().year()))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: t.accentColorHex))
                    Rectangle()
                        .fill(Color(hex: t.accentColorHex).opacity(0.4))
                        .frame(width: 90, height: 1)
                }
            }
            .padding(.bottom, 4)

            // Render Full-Width Blocks
            ForEach(t.blocks.filter { $0.column == .fullWidth }) { block in
                renderEditableBlock(block, t: t)
            }

            // Render Columns
            if t.layoutType == "twoColumnSplit" {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(t.blocks.filter { $0.column == .left }) { block in
                            renderEditableBlock(block, t: t)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 10) {
                        ForEach(t.blocks.filter { $0.column == .right }) { block in
                            renderEditableBlock(block, t: t)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(t.blocks.filter { $0.column != .fullWidth }) { block in
                    renderEditableBlock(block, t: t)
                }
            }
        }
        .padding(16)
        .background(Color(hex: t.backgroundColorHex))
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(t.cornerRadius) + 4))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(t.cornerRadius) + 4)
                .stroke(Color(hex: t.borderColorHex), lineWidth: CGFloat(t.borderWidth))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
    }

    private func renderEditableBlock(_ block: TemplateBlockConfig, t: ReportTemplate) -> some View {
        let sectionBinding = Binding<String>(
            get: {
                report.sections.first(where: { $0.heading.lowercased() == block.title.lowercased() })?.text ?? ""
            },
            set: { newValue in
                if let idx = report.sections.firstIndex(where: { $0.heading.lowercased() == block.title.lowercased() }) {
                    report.sections[idx].text = newValue
                } else {
                    report.sections.append(ReportSection(heading: block.title, text: newValue, column: block.column.rawValue, blockType: block.blockType.rawValue))
                }
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text(block.title)
                .font(.custom(fontFamilyName(t), size: 10).weight(.bold))
                .foregroundStyle(Color(hex: t.accentColorHex))
                .tracking(0.3)

            TextField(block.placeholder.isEmpty ? "Clinical findings & notes…" : block.placeholder, text: sectionBinding, axis: .vertical)
                .font(.custom(fontFamilyName(t), size: 12))
                .foregroundStyle(.black)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, minHeight: block.minHeight, alignment: .topLeading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(t.cornerRadius))
                .fill(block.column == .right || block.blockType == .vitalsGrid ? Color(hex: t.cardTintHex) : .white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(t.cornerRadius))
                .stroke(Color(hex: t.borderColorHex), lineWidth: CGFloat(t.borderWidth))
        )
    }

    private func fontFamilyName(_ t: ReportTemplate) -> String {
        switch t.fontFamily {
        case "serif": return "Georgia"
        case "mono": return "Menlo"
        default: return "Helvetica Neue"
        }
    }

    private func commitNewSection() {
        let heading = newSectionHeading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else { return }
        DS.haptic(.light)
        report.sections.append(ReportSection(heading: heading, text: ""))
        newSectionHeading = ""
    }

    /// Re-route this report onto another template. Text already dictated is
    /// carried over wherever the heading matches; missing blocks fall back to
    /// the template's default content.
    private func applyTemplate(_ template: ReportTemplate) {
        DS.haptic(.medium)
        let existing = report.sections
        report.template = template

        if !template.blocks.isEmpty {
            report.sections = template.blocks.map { block in
                ReportSection(
                    heading: block.title,
                    text: existing.first(where: { $0.heading.lowercased() == block.title.lowercased() })?.text
                        ?? block.defaultContent,
                    column: block.column.rawValue,
                    blockType: block.blockType.rawValue
                )
            }
        } else {
            report.sections = template.headings.map { heading in
                ReportSection(
                    heading: heading,
                    text: existing.first(where: { $0.heading.lowercased() == heading.lowercased() })?.text ?? ""
                )
            }
        }
    }

    private func deleteSection(_ id: UUID) {
        DS.haptic(.medium)
        report.sections.removeAll { $0.id == id }
    }

    // MARK: - Actions

    private func signReport() {
        report.status = .signed
        report.signedAt = Date()
        report.updatedAt = Date()
        try? context.save()
        DS.haptic(.heavy)
    }

    private func generateShareText() -> String {
        var text = "\(report.title)\n\n"
        if let p = report.patient {
            text += "Patient: \(p.name)\n"
            if !p.mrn.isEmpty { text += "MRN: \(p.mrn)\n" }
        }
        text += "\n"
        for section in report.sections {
            text += "\(section.heading.uppercased())\n\(section.text)\n\n"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendWhatsApp() {
        let phone = report.patient?.phone ?? ""
        let text = WhatsAppDispatchService.shared.generateWhatsAppText(
            patient: report.patient,
            report: report,
            clinic: clinic,
            voiceSummary: report.patientAdviceSummary
        )
        WhatsAppDispatchService.shared.dispatchToWhatsApp(phoneNumber: phone, text: text)
        DS.haptic(.medium)
    }

    private func copyPlainText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = report.plainText
        #endif
        DS.haptic(.light)
    }

    private func printReport() {
        #if canImport(UIKit)
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = report.title
        printInfo.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = ReportRenderer.pdf(for: report, clinic: clinic)
        controller.present(animated: true)
        #endif
    }

    private func autoFillTemplate() {
        isAutoFilling = true
        let rawContent = report.plainText.isEmpty ? report.title : report.plainText
        let headings = report.sections.map { $0.heading }

        Task {
            do {
                let filled = try await llm.fillTemplateFromSpeech(
                    speech: rawContent,
                    templateHeadings: headings,
                    templateName: report.template?.name ?? "Medical Report"
                )

                await MainActor.run {
                    for (headingKey, textValue) in filled {
                        if let idx = report.sections.firstIndex(where: { $0.heading.lowercased() == headingKey.lowercased() }) {
                            report.sections[idx].text = textValue
                            report.sections[idx].isAIPolished = true
                        }
                    }
                    isAutoFilling = false
                    DS.haptic(.medium)
                }
            } catch {
                await MainActor.run { isAutoFilling = false }
            }
        }
    }

    private func polishSection(section: ReportSection) {
        guard !section.text.isEmpty else { return }
        Task {
            do {
                var newText = ""
                try await llm.polishStreaming(section.text, section: section.heading) { chunk in
                    newText += chunk
                }
                await MainActor.run {
                    if let idx = report.sections.firstIndex(where: { $0.id == section.id }) {
                        report.sections[idx].text = newText
                        report.sections[idx].isAIPolished = true
                    }
                    DS.haptic(.light)
                }
            } catch {}
        }
    }
}

struct PatientSelectionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Patient.createdAt, order: .reverse) private var patients: [Patient]
    let report: RadiologyReport

    @State private var searchText = ""
    @State private var showCreateForm = false

    // Create new patient states
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var newSex = "M"
    @State private var newDOB = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    var filtered: [Patient] {
        if searchText.isEmpty { return patients }
        return patients.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.phone.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if showCreateForm {
                    createForm
                } else {
                    patientList
                }
            }
            .navigationTitle(showCreateForm ? "New Patient" : "Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if showCreateForm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveNewPatient() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showCreateForm = true
                        } label: {
                            Label("Add Patient", systemImage: "plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    private var patientList: some View {
        List {
            Section {
                ForEach(filtered) { p in
                    Button {
                        select(p)
                    } label: {
                        HStack(spacing: 12) {
                            Text(String(p.name.split(separator: " ").compactMap(\.first).prefix(2)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(DS.coralGradient()))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 15, weight: .bold)).foregroundStyle(.primary)
                                Text("\(p.age)y · \(p.sex) · \(p.phone.isEmpty ? "No phone" : p.phone)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if report.patient?.persistentModelID == p.persistentModelID {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DS.coral)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if filtered.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(DS.subAdaptive)
                        Text("No patients found")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
            }

            Section {
                Button {
                    showCreateForm = true
                } label: {
                    Label("Add New Patient", systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.coral)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Name or Phone")
    }

    private var createForm: some View {
        Form {
            Section("New Patient Info") {
                TextField("Full name", text: $newName)
                TextField("Phone Number", text: $newPhone).keyboardType(.phonePad)
                Picker("Sex", selection: $newSex) {
                    Text("M").tag("M"); Text("F").tag("F"); Text("Other").tag("Other")
                }
                DatePicker("Date of Birth", selection: $newDOB, displayedComponents: .date)
            }
        }
    }

    private func select(_ patient: Patient) {
        report.patient = patient
        try? context.save()
        DS.haptic(.light)
        dismiss()
    }

    private func saveNewPatient() {
        let p = Patient(name: newName, dateOfBirth: newDOB, sex: newSex, phone: newPhone)
        context.insert(p)
        try? context.save()
        report.patient = p
        try? context.save()
        DS.haptic(.light)
        dismiss()
    }
}
