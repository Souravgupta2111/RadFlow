import SwiftUI
import SwiftData

/// Template hub — use (set as default for dictation), create, edit, duplicate
/// or delete report templates. Built-ins come from the shared `TemplatePresets`
/// catalog and can be duplicated into editable copies.
struct TemplatesListView: View {
    @Query(sort: \ReportTemplate.name) private var templates: [ReportTemplate]
    @Environment(\.modelContext) private var context
    @AppStorage("report.defaultTemplateName") private var defaultTemplateName = ""
    @State private var templateToEdit: ReportTemplate?
    @State private var showModularBuilder = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerBanner

                if templates.isEmpty {
                    Tile(height: 170) {
                        VStack(spacing: 10) {
                            Image(systemName: "square.split.2x1")
                                .font(.system(size: 32))
                                .foregroundStyle(DS.subAdaptive)
                            Text("No templates yet")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Create one — or reload a built-in preset from the builder.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.subAdaptive)
                        }
                        .frame(maxWidth: .infinity, minHeight: 130)
                    }
                } else {
                    ForEach(templates) { template in
                        templateRow(template)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showModularBuilder) {
            ModularTemplateBuilderView(templateToEdit: templateToEdit)
                .modelContext(context)
        }
    }

    private var headerBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report Templates")
                    .font(DS.display(40))
                    .tracking(-1.6)
                    .foregroundStyle(DS.inkAdaptive)
            }
            Spacer()
            CircleButton(systemName: "plus") {
                templateToEdit = nil
                showModularBuilder = true
            }
        }
        .padding(.horizontal, 4)
    }

    private func templateRow(_ template: ReportTemplate) -> some View {
        let isDefault = template.name == defaultTemplateName

        return Tile {
            HStack(spacing: 12) {
                Button {
                    templateToEdit = template
                    showModularBuilder = true
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: template.accentColorHex.isEmpty ? "#0F172A" : template.accentColorHex))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: template.layoutType == "twoColumnSplit" ? "rectangle.split.2x1" : "doc.text")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.inkAdaptive)

                            HStack(spacing: 6) {
                                Text(template.layoutType == "twoColumnSplit" ? "2-Col" : "1-Col")
                                if !template.modality.isEmpty {
                                    Text("•")
                                    Text(template.modality)
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(DS.subAdaptive)
                            .lineLimit(1)
                        }

                        Spacer(minLength: 8)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    DS.haptic(.light)
                    defaultTemplateName = isDefault ? "" : template.name
                } label: {
                    Text(isDefault ? "Default" : "Set Default")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isDefault ? .white : DS.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(isDefault ? DS.coral : DS.coral.opacity(0.15)))
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.subAdaptive)
            }
        }
        .contextMenu {
            Button {
                DS.haptic(.light)
                defaultTemplateName = template.name
            } label: {
                Label("Use as Default", systemImage: "star")
            }
            Button {
                duplicate(template)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            if !template.isBuiltIn {
                Button(role: .destructive) {
                    context.delete(template)
                    try? context.save()
                } label: {
                    Label("Delete Template", systemImage: "trash")
                }
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func duplicate(_ template: ReportTemplate) {
        let copy = ReportTemplate(
            name: "\(template.name) (Copy)",
            modality: template.modality,
            headings: template.headings,
            macros: template.macros,
            isBuiltIn: false,
            layoutType: template.layoutType,
            accentColorHex: template.accentColorHex,
            backgroundColorHex: template.backgroundColorHex,
            cardTintHex: template.cardTintHex,
            borderColorHex: template.borderColorHex,
            fontFamily: template.fontFamily,
            borderWidth: template.borderWidth,
            cornerRadius: template.cornerRadius,
            headerTitle: template.headerTitle,
            subtitle: template.subtitle,
            blocks: template.blocks
        )
        context.insert(copy)
        try? context.save()
        DS.haptic(.medium)
    }
}
