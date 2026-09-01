import SwiftUI
import SwiftData
import PhotosUI

struct XrayAttachView: View {
    @Bindable var report: RadiologyReport
    @State private var picked: [PhotosPickerItem] = []
    @State private var analysis: [String] = []
    @State private var analyzing = false
    @State private var selectedSection: String = "Findings"
    @State private var selectedImageIndex: Int? = nil
    private let llm = LLMProvider.service

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Imaging")
                    .font(DS.display(40))
                    .tracking(-1.4)
                    .foregroundStyle(DS.inkAdaptive)

                pickerCard
                if !report.imageItems.isEmpty { gridCard }
                analyzeButton
                if analyzing { progressCard }
                if !analysis.isEmpty { analysisCard }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 60)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(
            get: { selectedImageIndex != nil ? IdentifiableInt(id: selectedImageIndex!) : nil },
            set: { selectedImageIndex = $0?.id }
        )) { idx in
            FullScreenImageView(imageItems: report.imageItems, initialIndex: idx.id)
        }
    }

    private var pickerCard: some View {
        Tile(height: 170) {
            VStack(spacing: 12) {
                Image(systemName: "xray")
                    .font(.system(size: 38))
                    .foregroundStyle(DS.coral)
                PhotosPicker(selection: $picked, matching: .images) {
                    Text("Choose X-ray images")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(DS.coralGradient()))
                }
                Text("DICOM & PACS pull coming later.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.subAdaptive)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
        }
        .onChange(of: picked) {
            Task { await loadImages() }
        }
    }

    private func loadImages() async {
        for item in picked {
            if let data = try? await item.loadTransferable(type: Data.self),
               UIImage(data: data) != nil {
                // Avoid duplicates by simple count or you can do better deduplication
                report.imageItems.append(ImageItem(data: data))
            }
        }
        picked.removeAll()
    }

    private var gridCard: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(report.imageItems.enumerated()), id: \.offset) { index, imgItem in
                if let uiImage = UIImage(data: imgItem.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture {
                            selectedImageIndex = index
                        }
                }
            }
        }
    }

    private var analyzeButton: some View {
        Button {
            Task { await runAnalysis() }
        } label: {
            Label("Suggest considerations", systemImage: "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(DS.inkAdaptive))
        }
        .buttonStyle(.plain)
        .disabled(report.imageItems.isEmpty || analyzing)
    }

    private var progressCard: some View {
        Tile(height: 80) {
            HStack {
                ProgressView()
                Text("Analyzing imaging…").font(DS.bodyFont).foregroundStyle(DS.subAdaptive)
                Spacer()
            }
        }
    }

    private var availableSections: [String] {
        let hdgs = report.sections.map { $0.heading }
        return hdgs.isEmpty ? ["Findings"] : hdgs
    }

    private var analysisCard: some View {
        Tile {
            VStack(alignment: .leading, spacing: 12) {
                Text("CONSIDERATIONS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(DS.coralDeep)
                ForEach(Array(analysis.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                            .background(Circle().fill(DS.coral))
                        Text(s).font(DS.bodyFont).foregroundStyle(DS.inkAdaptive)
                    }
                }
                
                HStack {
                    Text("Inject into:").font(DS.bodyFont)
                    Picker("Section", selection: $selectedSection) {
                        ForEach(availableSections, id: \.self) { sec in
                            Text(sec).tag(sec)
                        }
                    }
                    .onAppear {
                        if !availableSections.contains(selectedSection) {
                            selectedSection = availableSections.first ?? "Findings"
                        }
                    }
                }
                .padding(.top, 4)
                
                PillButton(title: "Attach to report", filled: true) {
                    let text = "\n" + analysis.joined(separator: "\n")
                    if let idx = report.sections.firstIndex(where: { $0.heading == selectedSection }) {
                        report.sections[idx].text += text
                    } else {
                        report.sections.append(ReportSection(heading: selectedSection,
                                                             text: analysis.joined(separator: "\n")))
                    }
                    report.updatedAt = Date()
                    DS.haptic(.medium)
                    analysis.removeAll()
                }
            }
        }
    }

    private func runAnalysis() async {
        analyzing = true
        defer { analyzing = false }
        // Process up to 3 images max to avoid token limit overflow for this demo
        let imagesData = report.imageItems.prefix(3).compactMap { item -> Data? in
            UIImage(data: item.data)?.jpegData(compressionQuality: 0.6)
        }
        do {
            let differentials = try await llm.suggestDifferentials(reportText: report.plainText, images: imagesData)
            analysis = differentials.map { "- \($0.finding) (Conf: \($0.confidence)): \($0.basis)" }
        } catch {
            analysis = ["Analysis failed: \(error.localizedDescription)"]
        }
    }
}

struct IdentifiableInt: Identifiable {
    let id: Int
}
