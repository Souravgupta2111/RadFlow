import Foundation
import Network
import Combine

/// Live connection state for the wireless remote.
enum RemoteConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(String)   // host name
    case error(String)
}

/// A machine discovered on the local Wi-Fi via Bonjour.
struct DiscoveredMachine: Identifiable, Hashable {
    let id: UUID
    let name: String
    let endpoint: NWEndpoint
}

/// Discovers RadFlow desktop bridges on the local network (Bonjour `_ledis._tcp`)
/// and streams dictated text to the chosen machine over TCP. The desktop
/// companion types received text at the cursor. This is the entire backend for
/// the Wireless Remote tab — no WisprFlow dependency.
@MainActor
final class RemoteConnectionService: ObservableObject {
    @Published var discovered: [DiscoveredMachine] = []
    @Published var state: RemoteConnectionState = .disconnected
    @Published var isBrowsing = false
    @Published var lastSent: String = ""

    static let serviceType = "_ledis._tcp"

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var lastMachine: DiscoveredMachine?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 6
    private let queue = DispatchQueue.main

    // MARK: - Discovery

    func startBrowsing() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: Self.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: NWParameters())
        browser.stateUpdateHandler = { [weak self] s in
            DispatchQueue.main.async {
                switch s {
                case .ready, .waiting:
                    self?.isBrowsing = true
                case .failed(let err):
                    self?.isBrowsing = false
                    self?.state = .error(err.localizedDescription)
                case .cancelled:
                    self?.isBrowsing = false
                default:
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discovered = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredMachine(id: UUID(), name: name, endpoint: result.endpoint)
                }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discovered = []
    }

    // MARK: - Connection

    func connect(to machine: DiscoveredMachine) {
        disconnect()
        reconnectAttempts = 0
        lastMachine = machine
        openConnection(to: machine)
    }

    private func openConnection(to machine: DiscoveredMachine) {
        state = .connecting
        let conn = NWConnection(to: machine.endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] s in
            DispatchQueue.main.async {
                guard let self else { return }
                switch s {
                case .ready:
                    self.reconnectAttempts = 0
                    self.state = .connected(machine.name)
                case .failed(let err):
                    self.scheduleReconnect(reason: err.localizedDescription)
                case .waiting(let err):
                    // Keep trying while the endpoint is temporarily unreachable.
                    self.state = .connecting
                    _ = err
                case .cancelled:
                    if case .connected = self.state { self.state = .disconnected }
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
        connection = conn
    }

    /// Silently re-establishes the link if the desktop drops out
    /// (sleep, Wi-Fi hiccup) — the doctor never has to reconnect by hand.
    private func scheduleReconnect(reason: String) {
        guard let machine = lastMachine, reconnectAttempts < maxReconnectAttempts else {
            state = .error(reason)
            return
        }
        reconnectAttempts += 1
        state = .connecting
        let delay = Double(min(reconnectAttempts, 4)) * 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let machine = self.lastMachine else { return }
            self.openConnection(to: machine)
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        lastMachine = nil
        if case .connected = state { state = .disconnected }
    }

    // MARK: - Send

    /// Sends a line-delimited JSON text frame to the connected desktop.
    func send(text: String) {
        print("[REMOTE-DEBUG] send(text:) called with: \(text.prefix(80))")
        guard let connection else {
            print("[REMOTE-DEBUG] send FAILED — connection is nil")
            return
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            print("[REMOTE-DEBUG] send FAILED — cleaned text is empty")
            return
        }

        let payload: [String: String] = ["type": "text", "text": cleaned]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var frame = data
        frame.append(0x0A) // newline delimiter

        connection.send(content: frame, completion: .contentProcessed { [weak self] err in
            DispatchQueue.main.async {
                if let err {
                    self?.state = .error(err.localizedDescription)
                } else {
                    self?.lastSent = cleaned
                }
            }
        })
    }
}
