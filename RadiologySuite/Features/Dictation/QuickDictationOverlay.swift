import SwiftUI
import SwiftData

/// Floating, Wispr Flow-style push-to-talk dictation widget.
/// Enables 1-tap instant dictation from anywhere in the app with real-time filler stripping.
struct QuickDictationPill: View {
    @StateObject private var vm = DictationViewModel()
    @State private var isExpanded = false
    @State private var pulse = false
    var onFinished: (RadiologyReport) -> Void = { _ in }
    
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 8) {
            if isExpanded {
                expandedTranscriptCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            mainPill
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.isRecording)
    }

    private var mainPill: some View {
        HStack(spacing: 12) {
            // Microphone Button / Waveform Pulse
            Button {
                toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isRecording ? Color.red : DS.inkAdaptive)
                        .frame(width: 44, height: 44)
                        .scaleEffect(vm.isRecording ? (pulse ? 1.15 : 0.95) : 1.0)
                    
                    Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            // Status / Live Transcript Preview
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vm.isRecording ? "Listening (Wispr Flow)" : "Tap to Dictate")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(vm.isRecording ? .red : DS.inkAdaptive)
                    
                    if vm.isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .opacity(pulse ? 1.0 : 0.3)
                    }
                }
                
                Text(vm.transcript.isEmpty ? "Hinglish & Fillers auto-cleaned" : vm.transcript)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.subAdaptive)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !vm.transcript.isEmpty {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.subAdaptive)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)

                Button {
                    finishAndCreateReport()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DS.coral))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.15), radius: 18, y: 8)
        )
        .overlay(
            Capsule()
                .stroke(vm.isRecording ? Color.red.opacity(0.3) : Color.black.opacity(0.06), lineWidth: 1.5)
        )
    }

    private var expandedTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Cleaned Transcript")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.inkAdaptive)
                Spacer()
                Button("Clear") {
                    vm.discard()
                    isExpanded = false
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
            }
            
            ScrollView {
                Text(vm.transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkAdaptive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        )
    }

    private func toggleRecording() {
        DS.haptic(.medium)
        if vm.isRecording {
            vm.finish()
            pulse = false
        } else {
            vm.begin()
            isExpanded = true
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func finishAndCreateReport() {
        DS.haptic(.medium)
        vm.finish()
        Task {
            if let report = await vm.sendToReport(context: context) {
                onFinished(report)
            }
        }
        isExpanded = false
    }
}
