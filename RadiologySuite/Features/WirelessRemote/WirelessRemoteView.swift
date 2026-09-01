import SwiftUI
import SwiftData

/// Wireless Remote tab.
/// Pair once with a desktop on the same Wi-Fi, then just speak — every
/// recognized chunk is typed at the cursor on that machine while you talk.
/// Discovery/transport live in `RemoteConnectionService`; streaming dictation
/// in `LiveRemoteDictation`.
struct WirelessRemoteView: View {
    @StateObject private var conn = RemoteConnectionService()
    @StateObject private var dictation = LiveRemoteDictation()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if case .connected(let name) = conn.state {
                    connectedView(host: name)
                } else {
                    discoveryView
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { conn.startBrowsing() }
        .onDisappear {
            dictation.stop()
            conn.disconnect()
            conn.stopBrowsing()
        }
        .alert("Wireless Mic", isPresented: Binding(
            get: { dictation.errorMessage != nil },
            set: { if !$0 { dictation.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictation.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wireless Mic")
                    .font(DS.display(40))
                    .tracking(-1.4)
                    .foregroundStyle(DS.inkAdaptive)
            }
            Spacer()
            statusDot
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(dotColor.opacity(0.3), lineWidth: 4))
    }

    private var dotColor: Color {
        if dictation.isLive { return .green }
        switch conn.state {
        case .connected: return DS.coral
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return DS.subAdaptive
        }
    }

    // MARK: - Discovery

    private var discoveryView: some View {
        VStack(spacing: 14) {
            if case .error(let message) = conn.state {
                errorTile(message)
            }

            if conn.discovered.isEmpty {
                // Setup guide tile
                Tile {
                    VStack(spacing: 18) {
                        // Searching indicator
                        HStack(spacing: 10) {
                            if conn.isBrowsing {
                                ProgressView().tint(DS.coral)
                            } else {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 18))
                                    .foregroundStyle(DS.subAdaptive)
                            }
                            Text(conn.isBrowsing ? "Searching for desktops…" : "No desktops found")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.inkAdaptive)
                            Spacer()
                        }
                        
                        Divider()
                        
                        // Setup steps
                        VStack(alignment: .leading, spacing: 14) {
                            Text("FIRST-TIME SETUP")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(DS.subAdaptive)
                            
                            setupStep(number: "1", icon: "arrow.down.circle.fill",
                                      title: "Install Radflow Desktop Bridge",
                                      subtitle: "A lightweight app that runs silently in the background on your computer.")
                            
                            // Download buttons
                            HStack(spacing: 12) {
                                Button {
                                    if let url = URL(string: "https://github.com/Souravgupta2111/RadFlow/releases/latest/download/Radflow-Desktop-Mac.zip") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "apple.logo")
                                        Text("Mac")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(DS.coralGradient()))
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    if let url = URL(string: "https://github.com/Souravgupta2111/RadFlow/releases/latest/download/Radflow-Desktop.exe") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "window")
                                        Text("Windows")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(DS.coralGradient()))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            setupStep(number: "2", icon: "desktopcomputer",
                                      title: "Open the Bridge on your computer",
                                      subtitle: "Double-click the downloaded app. It runs in your system tray / menu bar.")
                            
                            setupStep(number: "3", icon: "wifi",
                                      title: "Same Wi-Fi, auto-connect",
                                      subtitle: "Your computer will appear here automatically. No IP address needed.")
                        }
                    }
                }
                
                // macOS permission note
                Tile {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.coral)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("macOS Users")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DS.inkAdaptive)
                            Text("Grant Accessibility permission to Radflow Desktop in System Settings → Privacy & Security → Accessibility so it can type at your cursor.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.subAdaptive)
                        }
                    }
                }
            } else {
                sectionLabel("AVAILABLE DESKTOPS")
                ForEach(conn.discovered) { machine in
                    machineRow(machine)
                }
            }
        }
    }
    
    private func setupStep(number: String, icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.coral.opacity(0.12))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.coral)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.inkAdaptive)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.subAdaptive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func machineRow(_ machine: DiscoveredMachine) -> some View {
        Button {
            DS.haptic(.light)
            conn.connect(to: machine)
        } label: {
            Tile {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.coral)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.coral.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(machine.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.inkAdaptive)
                        Text("LEDIS Bridge · same Wi-Fi")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.subAdaptive)
                    }
                    Spacer()
                    if case .connecting = conn.state {
                        ProgressView().tint(DS.coral)
                    } else {
                        Text("Connect")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(DS.coral))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func errorTile(_ message: String) -> some View {
        Tile {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.inkAdaptive)
                Spacer()
            }
        }
    }

    // MARK: - Connected (live mic)

    private func connectedView(host: String) -> some View {
        VStack(spacing: 16) {
            coralHero(host: host)
            if !dictation.typedLog.isEmpty {
                typedFeed
            }
            helpCard
        }
    }

    private func coralHero(host: String) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dictation.isLive ? Color(hex: "#7DE8C4") : Color.white.opacity(0.7))
                    .frame(width: 9, height: 9)
                Text(dictation.isLive ? "LIVE · typing at cursor" : "Connected to \(host)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    DS.haptic(.light)
                    dictation.stop()
                    conn.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }

            micButton

            if dictation.isLive {
                Waveform(level: dictation.level)
            }

            Text(liveText)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
                .lineLimit(3)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(DS.coralGradient()))
        .shadow(color: DS.coral.opacity(0.3), radius: 20, y: 10)
    }

    private var micButton: some View {
        Button {
            DS.haptic(.medium)
            if dictation.isLive {
                dictation.stop()
            } else {
                dictation.start(connection: conn)
            }
        } label: {
            ZStack {
                if dictation.isLive {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 4)
                        .frame(width: 176, height: 176)
                        .scaleEffect(1.06)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dictation.isLive)
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 138, height: 138)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                Image(systemName: dictation.isLive ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(DS.coral)
            }
        }
        .buttonStyle(.plain)
    }

    private var liveText: String {
        if dictation.isLive {
            return dictation.liveTail.isEmpty ? "Listening… just speak, it types as you go" : dictation.liveTail
        }
        return "Tap the mic and speak. Everything you say appears at the cursor on \(hostName)."
    }

    private var hostName: String {
        if case .connected(let name) = conn.state { return name }
        return "your desktop"
    }

    // MARK: - Typed feed

    private var typedFeed: some View {
        Tile {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Typed at cursor", systemImage: "cursorarrow.rays")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                    Spacer()
                    Text("\(dictation.typedLog.count) chunks")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.coral)
                }
                ForEach(Array(dictation.typedLog.prefix(4).enumerated()), id: \.offset) { _, chunk in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .padding(.top, 2)
                        Text(chunk)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DS.inkAdaptive)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    // MARK: - Help

    private var helpCard: some View {
        Tile {
            VStack(alignment: .leading, spacing: 10) {
                Label("How it works", systemImage: "questionmark.circle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.inkAdaptive)
                infoRow("wifi", "Stays on your local Wi-Fi — nothing leaves the network.")
                infoRow("mic.fill", "Tap mic once and speak. Chunks type at the cursor live.")
                infoRow("arrow.triangle.2.circlepath", "If the desktop drops, LEDIS reconnects on its own.")
            }
        }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.coral)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DS.subAdaptive)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(DS.subAdaptive)
            .padding(.top, 6)
    }
}
