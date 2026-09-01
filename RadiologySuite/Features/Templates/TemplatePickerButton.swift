import SwiftUI
import SwiftData

struct TemplatePickerButton: View {
    @Binding var selectedTemplate: ReportTemplate?
    let modality: String
    
    @Query private var allTemplates: [ReportTemplate]
    
    init(selectedTemplate: Binding<ReportTemplate?>, modality: String) {
        self._selectedTemplate = selectedTemplate
        self.modality = modality
        let sortDescriptors = [SortDescriptor(\ReportTemplate.name)]
        self._allTemplates = Query(sort: sortDescriptors)
    }
    
    var body: some View {
        Menu {
            Button("No Template (Default)") {
                selectedTemplate = nil
            }
            
            Divider()
            
            ForEach(allTemplates) { template in
                Button {
                    selectedTemplate = template
                } label: {
                    HStack {
                        Text(template.name)
                        if template.layoutType == "twoColumnSplit" {
                            Text("· 2-Col")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedTemplate?.name ?? "Template: Default")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.15)))
        }
        .onAppear {
            if selectedTemplate == nil, let first = allTemplates.first(where: { $0.modality == modality }) {
                selectedTemplate = first
            }
        }
        .onChange(of: modality) { _, newModality in
            if selectedTemplate?.modality != newModality {
                selectedTemplate = allTemplates.first(where: { $0.modality == newModality })
            }
        }
    }
}
