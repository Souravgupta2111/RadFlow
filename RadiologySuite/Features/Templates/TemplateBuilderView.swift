import SwiftUI
import SwiftData

struct TemplateBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var modality: String = "Chest XR"
    @State private var headings: [String] = []
    @State private var macros: [VoiceMacro] = []
    
    @State private var newHeading: String = ""
    @State private var newMacroTrigger: String = ""
    @State private var newMacroExpansion: String = ""
    @State private var newMacroTargetHeading: String = ""

    var templateToEdit: ReportTemplate?

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Template Name", text: $name)
                    Picker("Modality", selection: $modality) {
                        ForEach(["Chest XR", "CT Head", "MRI Brain", "US Abdomen", "Other"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }

                Section("Headings") {
                    List {
                        ForEach(headings.indices, id: \.self) { index in
                            TextField("Heading", text: Binding(
                                get: { headings[index] },
                                set: { headings[index] = $0 }
                            ))
                        }
                        .onDelete { headings.remove(atOffsets: $0) }
                        .onMove { headings.move(fromOffsets: $0, toOffset: $1) }
                    }
                    
                    HStack {
                        TextField("New Heading", text: $newHeading)
                            .onSubmit { addHeading() }
                        Button(action: addHeading) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newHeading.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Voice Macros") {
                    ForEach(macros.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Trigger (e.g. 'normal heart')", text: Binding(
                                get: { macros[index].trigger },
                                set: { macros[index].trigger = $0 }
                            ))
                            .font(.headline)
                            
                            TextField("Expansion", text: Binding(
                                get: { macros[index].expansion },
                                set: { macros[index].expansion = $0 }
                            ))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            
                            Picker("Target Heading", selection: Binding(
                                get: { macros[index].targetHeading },
                                set: { macros[index].targetHeading = $0 }
                            )) {
                                Text("Any").tag("")
                                ForEach(headings, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { macros.remove(atOffsets: $0) }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Macro").font(.caption).foregroundColor(.secondary)
                        TextField("Trigger (e.g. 'normal lungs')", text: $newMacroTrigger)
                        TextField("Expansion (e.g. 'The lungs are clear without consolidation or effusion.')", text: $newMacroExpansion)
                        Picker("Target Heading", selection: $newMacroTargetHeading) {
                            Text("Any").tag("")
                            ForEach(headings, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        Button("Add Macro") {
                            addMacro()
                        }
                        .disabled(newMacroTrigger.isEmpty || newMacroExpansion.isEmpty)
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(templateToEdit == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton() // Enables drag-to-reorder
                }
            }
            .onAppear {
                if let template = templateToEdit {
                    name = template.name
                    modality = template.modality
                    headings = template.headings
                    macros = template.macros
                } else if headings.isEmpty {
                    headings = ["Clinical History", "Technique", "Findings", "Impression"]
                }
            }
        }
    }

    private func addHeading() {
        let trimmed = newHeading.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        headings.append(trimmed)
        newHeading = ""
    }

    private func addMacro() {
        let trigger = newMacroTrigger.trimmingCharacters(in: .whitespaces)
        let expansion = newMacroExpansion.trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !expansion.isEmpty else { return }
        macros.append(VoiceMacro(trigger: trigger, expansion: expansion, targetHeading: newMacroTargetHeading))
        newMacroTrigger = ""
        newMacroExpansion = ""
    }

    private func save() {
        if let template = templateToEdit {
            template.name = name
            template.modality = modality
            template.headings = headings
            template.macros = macros
        } else {
            let template = ReportTemplate(name: name, modality: modality, headings: headings, macros: macros)
            context.insert(template)
        }
        try? context.save()
        dismiss()
    }
}
