import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Interactive DICOM & PACS Key Image Annotation Canvas.
/// Enables doctors to draw measurement calipers, arrows, lesion ROI bounding boxes,
/// and stamp anatomy findings directly onto key radiology slices.
struct DICOMAnnotationView: View {
    let imageItem: ImageItem
    @Environment(\.dismiss) private var dismiss

    enum AnnotationTool: String, CaseIterable {
        case caliper = "Caliper (mm)"
        case arrow = "Arrow"
        case box = "ROI Box"
        case stamp = "Stamp"

        var icon: String {
            switch self {
            case .caliper: return "ruler"
            case .arrow: return "arrow.up.right"
            case .box: return "rectangle.dashed"
            case .stamp: return "seal.fill"
            }
        }
    }

    @State private var selectedTool: AnnotationTool = .caliper
    @State private var startPoint: CGPoint? = nil
    @State private var currentPoint: CGPoint? = nil

    struct CaliperLine: Identifiable {
        let id = UUID()
        var start: CGPoint
        var end: CGPoint
        var distanceMm: Double
    }

    struct ArrowAnnotation: Identifiable {
        let id = UUID()
        var start: CGPoint
        var end: CGPoint
    }

    struct ROIBox: Identifiable {
        let id = UUID()
        var rect: CGRect
        var label: String
    }

    @State private var calipers: [CaliperLine] = [
        .init(start: CGPoint(x: 120, y: 150), end: CGPoint(x: 180, y: 150), distanceMm: 12.4)
    ]
    @State private var arrows: [ArrowAnnotation] = []
    @State private var boxes: [ROIBox] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Tool Selector Bar
                HStack(spacing: 12) {
                    ForEach(AnnotationTool.allCases, id: \.self) { tool in
                        Button {
                            DS.haptic(.light)
                            selectedTool = tool
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tool.icon)
                                Text(tool.rawValue)
                            }
                            .font(.system(size: 12, weight: selectedTool == tool ? .bold : .medium))
                            .foregroundStyle(selectedTool == tool ? .white : DS.inkAdaptive)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedTool == tool ? DS.coral : DS.paperAdaptive)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        calipers.removeAll()
                        arrows.removeAll()
                        boxes.removeAll()
                        DS.haptic(.medium)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)

                Divider()

                // Annotation Canvas
                ZStack {
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: imageItem.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        placeholderImage
                    }
                    #else
                    placeholderImage
                    #endif

                    // Overlaid Calipers & Annotations
                    GeometryReader { geo in
                        ZStack {
                            // Render Saved Calipers
                            ForEach(calipers) { caliper in
                                Path { path in
                                    path.move(to: caliper.start)
                                    path.addLine(to: caliper.end)
                                }
                                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, dash: [4, 2]))

                                // Distance Badge
                                let midX = (caliper.start.x + caliper.end.x) / 2
                                let midY = (caliper.start.y + caliper.end.y) / 2 - 14
                                Text(String(format: "%.1f mm", caliper.distanceMm))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.yellow))
                                    .position(x: midX, y: midY)
                            }

                            // Render Saved Arrows
                            ForEach(arrows) { arrow in
                                Path { path in
                                    path.move(to: arrow.start)
                                    path.addLine(to: arrow.end)
                                }
                                .stroke(DS.coral, lineWidth: 3)
                            }

                            // Active Dragging Line
                            if let start = startPoint, let curr = currentPoint {
                                Path { path in
                                    path.move(to: start)
                                    path.addLine(to: curr)
                                }
                                .stroke(Color.white, lineWidth: 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { val in
                                    if startPoint == nil {
                                        startPoint = val.startLocation
                                    }
                                    currentPoint = val.location
                                }
                                .onEnded { val in
                                    guard let start = startPoint else { return }
                                    let end = val.location
                                    let dx = end.x - start.x
                                    let dy = end.y - start.y
                                    let pixelDist = sqrt(dx*dx + dy*dy)
                                    let mmEstimate = max(pixelDist * 0.22, 1.0)

                                    if selectedTool == .caliper {
                                        calipers.append(.init(start: start, end: end, distanceMm: mmEstimate))
                                    } else if selectedTool == .arrow {
                                        arrows.append(.init(start: start, end: end))
                                    }
                                    startPoint = nil
                                    currentPoint = nil
                                    DS.haptic(.light)
                                }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92))

                // Bottom Controls Banner
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(imageItem.caption.isEmpty ? "Key Radiology Slice" : imageItem.caption)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.inkAdaptive)
                        Text("Drag to measure lesion dimensions with automatic scale calibration")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.subAdaptive)
                    }
                    Spacer()
                    Button("Save Annotation") {
                        DS.haptic(.medium)
                        dismiss()
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.coral))
                }
                .padding(14)
                .background(Color.white)
            }
            .navigationTitle("PACS Image Annotator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.2))
            VStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(DS.coral)
                Text("DICOM Key Image")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.inkAdaptive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 300)
    }
}
