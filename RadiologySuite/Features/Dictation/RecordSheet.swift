import SwiftUI
import SwiftData
import Combine
import UIKit

struct RecordSheet: View {
    var preselectedPatient: Patient? = nil
    var onDone: (RadiologyReport?) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ReportTemplate.name) private var templates: [ReportTemplate]
    @AppStorage("report.defaultTemplateName") private var defaultTemplateName = ""
    @StateObject private var vm = DictationViewModel()
    @State private var startDate = Date()
    @State private var pausedAt: Date?
    @State private var now = Date()

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? DS.paperAdaptive : DS.coral).ignoresSafeArea()
            VStack(spacing: 0) {
                header

                templateBar
                    .padding(.top, 10)

                transcriptPreview
                    .padding(.top, 14)
                    .frame(maxHeight: .infinity)

                timerArea
                    .padding(.top, 12)
                controls
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            if vm.isProcessingAI {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Structuring your report...")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            vm.begin()
            startDate = Date()
            if let p = preselectedPatient {
                vm.patientName = p.name
            }
            if vm.selectedTemplate == nil {
                vm.selectedTemplate = templates.first { $0.name == defaultTemplateName }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            vm.finish()
        }
        .alert("Dictation Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let msg = vm.errorMessage {
                Text(msg)
            }
        }
        .onReceive(timer) { now = $0 }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Button {
                vm.discard()
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.25)))
            }
            .buttonStyle(.plain)

            Spacer()
            
            Text(vm.isPaused ? "Paused" : "Listening")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// Pick which template (parcha pad / chart / radiology format) this
    /// dictation is routed into. Persisted as the default for next time.
    private var templateBar: some View {
        HStack {
            Menu {
                Button("Plain Sections (No Template)") { selectTemplate(nil) }
                ForEach(templates) { template in
                    Button {
                        selectTemplate(template)
                    } label: {
                        if vm.selectedTemplate?.id == template.id {
                            Label(template.name, systemImage: "checkmark")
                        } else {
                            Text(template.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11, weight: .semibold))
                    Text(vm.selectedTemplate?.name ?? "Template")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            Spacer()
            if vm.selectedTemplate != nil {
                Label("AI fills sections", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func selectTemplate(_ template: ReportTemplate?) {
        DS.haptic(.light)
        vm.selectedTemplate = template
        defaultTemplateName = template?.name ?? ""
    }

    private var transcriptPreview: some View {
        ZStack(alignment: .topLeading) {
            if vm.transcript.isEmpty {
                Text("Speak your findings, or tap to type…")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            LiveTranscriptEditor(
                text: Binding(
                    get: { vm.transcript },
                    set: { vm.applyUserEdit($0) }
                ),
                onEditingChange: { editing in
                    vm.isEditingTranscript = editing
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.12)))
    }

    private var elapsedText: String {
        let end = pausedAt ?? now
        let secs = max(0, Int(end.timeIntervalSince(startDate)))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private var timerArea: some View {
        TimerBox(text: elapsedText)
            .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack {
            PillButton(title: paused ? "Resume" : "Pause", filled: true) { togglePause() }
            Spacer()
            Button {
                DS.haptic(.medium)
                vm.finish()
                Task {
                    let report = await vm.sendToReport(context: context)
                    onDone(report)
                }
            } label: {
                if vm.isProcessingAI {
                    ProgressView().tint(DS.paperAdaptive)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(DS.inkAdaptive))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DS.paperAdaptive)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(DS.inkAdaptive))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(vm.isProcessingAI)
        }
    }

    private var paused: Bool { pausedAt != nil }

    private func togglePause() {
        DS.haptic(.light)
        if let p = pausedAt {
            startDate = startDate.addingTimeInterval(now.timeIntervalSince(p))
            pausedAt = nil
            vm.resume()
        } else {
            pausedAt = Date()
            vm.pause()
        }
    }
}

/// Editable transcript that pins to the latest line as dictation grows.
private struct LiveTranscriptEditor: UIViewRepresentable {
    @Binding var text: String
    var onEditingChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChange: onEditingChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .white
        view.tintColor = .white
        view.font = .systemFont(ofSize: 15)
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 28, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.text != text else { return }
        context.coordinator.isProgrammatic = true
        view.text = text
        context.coordinator.scrollToEnd(view)
        DispatchQueue.main.async {
            context.coordinator.isProgrammatic = false
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var onEditingChange: (Bool) -> Void
        var isProgrammatic = false

        init(text: Binding<String>, onEditingChange: @escaping (Bool) -> Void) {
            self.text = text
            self.onEditingChange = onEditingChange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            onEditingChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            onEditingChange(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammatic else { return }
            text.wrappedValue = textView.text ?? ""
        }

        func scrollToEnd(_ textView: UITextView) {
            let length = (textView.text as NSString).length
            guard length > 0 else { return }
            let end = NSRange(location: length, length: 0)
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(end)
            }
        }
    }
}
