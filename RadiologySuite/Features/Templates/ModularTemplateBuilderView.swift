import SwiftUI
import SwiftData

/// Full "Canva / Word / PowerPoint" Modular Template Builder.
/// Features a live WYSIWYG interactive canvas preview, multi-column layouts (matching medical charts),
/// palette & typography selectors, and custom block managers.
struct ModularTemplateBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var templateToEdit: ReportTemplate?

    @State private var name: String = "Custom Medical Chart"
    @State private var modality: String = "General"
    @State private var headerTitle: String = "MEDICAL CHART"
    @State private var subtitle: String = "OUTPATIENT CLINICAL NOTE"
    @State private var layoutType: String = "twoColumnSplit"
    
    // Style Tokens (Canva Controls)
    @State private var accentColorHex: String = "#0F172A"
    @State private var backgroundColorHex: String = "#FFFFFF"
    @State private var cardTintHex: String = "#FFF1F2" // Pastel rose from user image
    @State private var borderColorHex: String = "#E2E8F0"
    @State private var fontFamily: String = "sans"
    @State private var borderWidth: Float = 1.0
    @State private var cornerRadius: Float = 4.0
    
    @State private var blocks: [TemplateBlockConfig] = []
    
    // Block editing state
    @State private var showAddBlock = false
    @State private var newBlockTitle = ""
    @State private var newBlockColumn: BlockColumn = .left
    @State private var newBlockType: BlockType = .text
    @State private var selectedTab = 0 // 0: Live Canvas, 1: Layout & Blocks, 2: Styling

    let colorPalettes = [
        ("Pastel", "#0F172A", "#FFF1F2", "#FDA4AF"),
        ("Azure", "#0284C7", "#F0F9FF", "#BAE6FD"),
        ("Emerald", "#059669", "#ECFDF5", "#A7F3D0"),
        ("Modern", "#1E293B", "#F8FAFC", "#CBD5E1"),
        ("Crimson", "#E11D48", "#FFF1F2", "#FECDD3")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Segmented Inspector
                Picker("View", selection: $selectedTab) {
                    Text("Canvas").tag(0)
                    Text("Section").tag(1)
                    Text("Styling").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(DS.card)

                ScrollView {
                    VStack(spacing: 20) {
                        if selectedTab == 0 {
                            liveDocumentPreview
                        } else if selectedTab == 1 {
                            blocksManagerSection
                        } else {
                            canvaStylingSection
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 60)
                }
            }
            .background(DS.paperAdaptive.ignoresSafeArea())
            .navigationTitle(templateToEdit == nil ? "Template Builder" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .tint(DS.coral)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                loadTemplate()
            }
            .sheet(isPresented: $showAddBlock) {
                addBlockSheet
            }
        }
    }

    // MARK: - 1. Live WYSIWYG Canva Document Preview
    private var liveDocumentPreview: some View {
        VStack(spacing: 12) {
            HStack {
                Text("LIVE CANVAS PREVIEW")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.subAdaptive)
                Spacer()
                Menu("Load Presets") {
                    ForEach(Array(TemplatePresets.all.enumerated()), id: \.offset) { _, preset in
                        Button(preset.name) { loadPreset(preset) }
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.coral)
            }

            // The Rendered Chart Sheet
            VStack(alignment: .leading, spacing: 10) {
                // Document Header (Matching user's image)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headerTitle)
                            .font(.custom(fontFamilyName, size: 24).weight(.heavy))
                            .foregroundStyle(Color(hex: accentColorHex))
                            .tracking(0.5)
                        Text(subtitle)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.subAdaptive)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DATE: \(Date.now.formatted(.dateTime.month().day().year()))")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: accentColorHex))
                        Rectangle()
                            .fill(Color(hex: accentColorHex).opacity(0.4))
                            .frame(width: 90, height: 1)
                    }
                }
                .padding(.bottom, 4)

                // Render Full-Width Blocks (e.g. Vitals Grid or Header Demographics)
                ForEach(blocks.filter { $0.column == .fullWidth }) { block in
                    renderBlockCard(block)
                }

                // Render 2-Column Split (Left vs Right)
                if layoutType == "twoColumnSplit" {
                    HStack(alignment: .top, spacing: 10) {
                        // Left Column (40% width in chart)
                        VStack(spacing: 10) {
                            ForEach(blocks.filter { $0.column == .left }) { block in
                                renderBlockCard(block)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Right Column (60% width in chart)
                        VStack(spacing: 10) {
                            ForEach(blocks.filter { $0.column == .right }) { block in
                                renderBlockCard(block)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Single Column Sequential
                    ForEach(blocks.filter { $0.column != .fullWidth }) { block in
                        renderBlockCard(block)
                    }
                }
            }
            .padding(16)
            .background(Color(hex: backgroundColorHex))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(cornerRadius) + 4))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(cornerRadius) + 4)
                    .stroke(Color(hex: borderColorHex), lineWidth: CGFloat(borderWidth))
            )
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)
        }
    }

    private func renderBlockCard(_ block: TemplateBlockConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.title)
                .font(.custom(fontFamilyName, size: 10).weight(.bold))
                .foregroundStyle(Color(hex: accentColorHex))
                .tracking(0.3)

            if block.blockType == .vitalsGrid {
                HStack(spacing: 6) {
                    vitalChip("BP", "120/80")
                    vitalChip("T", "98.6°F")
                    vitalChip("P", "72")
                    vitalChip("R", "16")
                    vitalChip("O2", "99%")
                    vitalChip("BMI", "22.4")
                }
            } else if block.blockType == .checkbox {
                HStack(spacing: 6) {
                    Image(systemName: "square")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.subAdaptive)
                    Text(block.placeholder.isEmpty ? "Review in 1 week" : block.placeholder)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.subAdaptive)
                }
            } else if block.blockType == .pencilKitDrawing {
                HStack {
                    Image(systemName: "pencil.tip.crop.circle")
                    Text("Apple Pencil sketchpad area")
                }
                .font(.system(size: 10))
                .foregroundStyle(DS.subAdaptive)
                .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                Text(block.placeholder.isEmpty ? "Clinical findings & notes…" : block.placeholder)
                    .font(.custom(fontFamilyName, size: 10.5))
                    .foregroundStyle(DS.subAdaptive.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: block.minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius))
                .fill(block.column == .right || block.blockType == .vitalsGrid ? Color(hex: cardTintHex) : DS.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(cornerRadius))
                .stroke(Color(hex: borderColorHex), lineWidth: CGFloat(borderWidth))
        )
    }

    private func vitalChip(_ label: String, _ val: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DS.subAdaptive)
            Text(val)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(hex: accentColorHex))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(DS.card))
    }

    // MARK: - 2. Sections & Blocks Manager
    private var blocksManagerSection: some View {
        VStack(spacing: 16) {
            Tile {
                VStack(alignment: .leading, spacing: 12) {
                    Text("General Template Details")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                    
                    TextField("Template Name", text: $name)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DS.paperAdaptive))

                    TextField("Header Banner Title (e.g. MEDICAL CHART)", text: $headerTitle)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DS.paperAdaptive))

                    TextField("Subtitle", text: $subtitle)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DS.paperAdaptive))
                }
            }

            Tile {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Section Blocks (\(blocks.count))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(DS.inkAdaptive)
                            Text("Reorder sections, change columns, or duplicate blocks")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.subAdaptive)
                        }
                        Spacer()
                        Button {
                            showAddBlock = true
                        } label: {
                            Label("Add Block", systemImage: "plus.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DS.coral)
                        }
                    }

                    ForEach(blocks.indices, id: \.self) { idx in
                        let block = blocks[idx]
                        HStack(spacing: 8) {
                            // Reorder (compact vertical chevrons)
                            VStack(spacing: 1) {
                                Button {
                                    if idx > 0 {
                                        blocks.swapAt(idx, idx - 1)
                                        DS.haptic(.light)
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(idx > 0 ? DS.inkAdaptive : Color.gray.opacity(0.3))
                                }
                                .disabled(idx == 0)

                                Button {
                                    if idx < blocks.count - 1 {
                                        blocks.swapAt(idx, idx + 1)
                                        DS.haptic(.light)
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(idx < blocks.count - 1 ? DS.inkAdaptive : Color.gray.opacity(0.3))
                                }
                                .disabled(idx == blocks.count - 1)
                            }
                            .frame(width: 20)

                            Image(systemName: blockIcon(block.blockType))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.coral)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(block.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.inkAdaptive)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(block.blockType.rawValue.capitalized)
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.subAdaptive)
                            }

                            Spacer(minLength: 4)

                            // Column placement (compact capsule menu)
                            Menu {
                                Button("Left Column") { blocks[idx].column = .left }
                                Button("Right Column") { blocks[idx].column = .right }
                                Button("Full Width") { blocks[idx].column = .fullWidth }
                            } label: {
                                Text(columnLabel(block.column))
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(DS.coral.opacity(0.12)))
                                    .foregroundStyle(DS.coral)
                            }

                            // Duplicate
                            Button {
                                var copy = block
                                copy.id = UUID()
                                copy.title = "\(copy.title) (COPY)"
                                blocks.insert(copy, at: idx + 1)
                                DS.haptic(.light)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.subAdaptive)
                            }
                            .buttonStyle(.plain)

                            // Delete
                            Button {
                                blocks.remove(at: idx)
                                DS.haptic(.medium)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(DS.paperAdaptive))
                    }
                }
            }
        }
    }

    // MARK: - 3. Canva Styling Controls
    private var canvaStylingSection: some View {
        VStack(spacing: 16) {
            Tile {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Curated Color Themes")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                    
                    HStack(spacing: 12) {
                        ForEach(colorPalettes, id: \.0) { item in
                            Button {
                                DS.haptic(.light)
                                accentColorHex = item.1
                                cardTintHex = item.2
                                borderColorHex = item.3
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(hex: item.2))
                                        .frame(width: 38, height: 38)
                                        .overlay(Circle().stroke(Color(hex: item.3), lineWidth: 2))
                                        .overlay(
                                            Circle()
                                                .fill(Color(hex: item.1))
                                                .frame(width: 14, height: 14)
                                        )
                                    Text(item.0)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(DS.inkAdaptive)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Tile {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Typography & Fonts")
                        .font(.system(size: 15, weight: .bold))
                    
                    Picker("Font Family", selection: $fontFamily) {
                        Text("Modern Sans").tag("sans")
                        Text("Classic Serif").tag("serif")
                        Text("Clinical Mono").tag("mono")
                    }
                    .pickerStyle(.segmented)

                    Text("Layout Mode")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.top, 6)

                    Picker("Layout", selection: $layoutType) {
                        Text("2-Column Split").tag("twoColumnSplit")
                        Text("Single Column").tag("singleColumn")
                    }
                    .pickerStyle(.segmented)
                }
            }

            Tile {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Borders & Corner Radiuses")
                        .font(.system(size: 15, weight: .bold))
                    
                    HStack {
                        Text("Corner Radius: \(Int(cornerRadius))px")
                            .font(.system(size: 12))
                        Spacer()
                        Slider(value: $cornerRadius, in: 0...16, step: 2)
                            .frame(width: 150)
                    }

                    HStack {
                        Text("Border Width: \(String(format: "%.1f", borderWidth))px")
                            .font(.system(size: 12))
                        Spacer()
                        Slider(value: $borderWidth, in: 0.5...3.0, step: 0.5)
                            .frame(width: 150)
                    }
                }
            }
        }
    }

    private var addBlockSheet: some View {
        NavigationStack {
            Form {
                Section("Block Details") {
                    TextField("Section Title (e.g. PHYSICAL EXAM)", text: $newBlockTitle)
                    Picker("Column Placement", selection: $newBlockColumn) {
                        Text("Left Column").tag(BlockColumn.left)
                        Text("Right Column").tag(BlockColumn.right)
                        Text("Full Width").tag(BlockColumn.fullWidth)
                    }
                    Picker("Block Type", selection: $newBlockType) {
                        Text("Standard Text").tag(BlockType.text)
                        Text("Vitals Grid").tag(BlockType.vitalsGrid)
                        Text("Checkbox List").tag(BlockType.checkbox)
                        Text("Apple Pencil Canvas").tag(BlockType.pencilKitDrawing)
                    }
                }
            }
            .navigationTitle("New Section Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAddBlock = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        blocks.append(TemplateBlockConfig(
                            title: newBlockTitle.uppercased(),
                            column: newBlockColumn,
                            blockType: newBlockType
                        ))
                        newBlockTitle = ""
                        showAddBlock = false
                    }
                    .disabled(newBlockTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var fontFamilyName: String {
        switch fontFamily {
        case "serif": return "Georgia"
        case "mono": return "Menlo"
        default: return "Helvetica Neue"
        }
    }

    private func blockIcon(_ type: BlockType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .vitalsGrid: return "heart.text.square"
        case .checkbox: return "checkmark.square"
        case .pencilKitDrawing: return "pencil.tip.crop.circle"
        }
    }

    private func columnLabel(_ column: BlockColumn) -> String {
        switch column {
        case .left: return "Left"
        case .right: return "Right"
        case .fullWidth: return "Full"
        }
    }

    // MARK: - Presets Loader (from shared catalog)

    private func loadPreset(_ preset: TemplatePresets.Preset) {
        name = preset.name
        headerTitle = preset.headerTitle
        subtitle = preset.subtitle
        layoutType = preset.layoutType
        accentColorHex = preset.accentColorHex
        backgroundColorHex = preset.backgroundColorHex
        cardTintHex = preset.cardTintHex
        borderColorHex = preset.borderColorHex
        fontFamily = preset.fontFamily
        borderWidth = preset.borderWidth
        cornerRadius = preset.cornerRadius
        blocks = preset.blocks
    }

    private func loadTemplate() {
        if let t = templateToEdit {
            name = t.name
            modality = t.modality
            headerTitle = t.headerTitle
            subtitle = t.subtitle
            layoutType = t.layoutType
            accentColorHex = t.accentColorHex
            backgroundColorHex = t.backgroundColorHex
            cardTintHex = t.cardTintHex
            borderColorHex = t.borderColorHex
            fontFamily = t.fontFamily
            borderWidth = t.borderWidth
            cornerRadius = t.cornerRadius
            blocks = t.blocks.isEmpty ? t.headings.map { TemplateBlockConfig(title: $0) } : t.blocks
        } else {
            loadPreset(TemplatePresets.all[0])
        }
    }

    private func saveTemplate() {
        DS.haptic(.medium)
        
        let existingNames = (try? context.fetch(FetchDescriptor<ReportTemplate>()))?.map(\.name) ?? []
        
        // If editing a user-created template, update it in place.
        // If editing a built-in preset, ALWAYS save as a new custom template instead of overwriting the preset.
        if let t = templateToEdit, !t.isBuiltIn {
            if name != t.name && existingNames.contains(name) {
                t.name = "\(name) (Copy)"
            } else {
                t.name = name
            }
            t.modality = modality
            t.headerTitle = headerTitle
            t.subtitle = subtitle
            t.layoutType = layoutType
            t.accentColorHex = accentColorHex
            t.backgroundColorHex = backgroundColorHex
            t.cardTintHex = cardTintHex
            t.borderColorHex = borderColorHex
            t.fontFamily = fontFamily
            t.borderWidth = borderWidth
            t.cornerRadius = cornerRadius
            t.blocks = blocks
            t.headings = blocks.map(\.title)
        } else {
            // Ensure strictly unique name if saving from a preset or if name already exists
            var finalName = name
            if existingNames.contains(finalName) {
                finalName = "\(finalName) (Custom)"
                if existingNames.contains(finalName) {
                    finalName = "\(finalName) \(Int.random(in: 10...999))"
                }
            }
            
            let newTemplate = ReportTemplate(
                name: finalName,
                modality: modality,
                headings: blocks.map(\.title),
                isBuiltIn: false,
                layoutType: layoutType,
                accentColorHex: accentColorHex,
                backgroundColorHex: backgroundColorHex,
                cardTintHex: cardTintHex,
                borderColorHex: borderColorHex,
                fontFamily: fontFamily,
                borderWidth: borderWidth,
                cornerRadius: cornerRadius,
                headerTitle: headerTitle,
                subtitle: subtitle,
                blocks: blocks
            )
            context.insert(newTemplate)
        }
        
        do {
            try context.save()
        } catch {
            print("Failed to save template: \(error)")
        }
    }
}
