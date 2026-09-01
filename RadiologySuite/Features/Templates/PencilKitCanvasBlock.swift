import SwiftUI
import PencilKit

/// Apple Pencil & Touch Drawing Component for Clinical Templates.
/// Allows doctors to sketch anatomical findings, circle lesions, or sign directly onto the chart.
struct PencilKitCanvasBlock: View {
    @Binding var drawingData: Data?
    var title: String = "Anatomical Sketch / Markup"
    var isEditable: Bool = true
    
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var showToolPicker = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "pencil.and.scribble")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.inkAdaptive)
                Spacer()
                if isEditable {
                    Button {
                        clearCanvas()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            PencilKitViewRepresentable(
                canvasView: $canvasView,
                toolPicker: $toolPicker,
                drawingData: $drawingData,
                isEditable: isEditable
            )
            .frame(height: 140)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.12), lineWidth: 1))
        }
    }

    private func clearCanvas() {
        DS.haptic(.light)
        canvasView.drawing = PKDrawing()
        drawingData = canvasView.drawing.dataRepresentation()
    }
}

struct PencilKitViewRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var toolPicker: PKToolPicker
    @Binding var drawingData: Data?
    var isEditable: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator

        if let data = drawingData, let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        }

        if isEditable {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if let data = drawingData, uiView.drawing.dataRepresentation() != data {
            if let drawing = try? PKDrawing(data: data) {
                uiView.drawing = drawing
            }
        }
        uiView.isUserInteractionEnabled = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilKitViewRepresentable

        init(_ parent: PencilKitViewRepresentable) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            DispatchQueue.main.async {
                self.parent.drawingData = canvasView.drawing.dataRepresentation()
            }
        }
    }
}
