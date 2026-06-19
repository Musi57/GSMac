import Foundation
import CryptoKit
import Observation

enum OBSConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

@Observable
final class OBSConnectionManager {
    static let shared = OBSConnectionManager()

    private(set) var state: OBSConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?

    private init() {}

    func connect(host: String, port: Int, password: String?) {
        disconnect()

        state = .connecting
        AppLogger.shared.log("Connecting to OBS at \(host):\(port)...", level: .info)

        guard let url = URL(string: "ws://\(host):\(port)") else {
            state = .failed("Invalid host/port")
            AppLogger.shared.log("Invalid OBS WebSocket URL", level: .error)
            return
        }

        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        receiveMessage(password: password)
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session = nil
        if state != .disconnected {
            state = .disconnected
        }
    }

    private func receiveMessage(password: String?) {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                self.state = .failed(error.localizedDescription)
                AppLogger.shared.log("OBS connection failed: \(error.localizedDescription)", level: .error)

            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text, password: password)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text, password: password)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage(password: password)
            }
        }
    }

    private func handleMessage(_ text: String, password: String?) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = json["op"] as? Int else { return }

        switch op {
        case 0: // Hello
            handleHello(json["d"] as? [String: Any] ?? [:], password: password)
        case 2: // Identified
            state = .connected
            AppLogger.shared.log("Connected to OBS successfully.", level: .info)
        default:
            break
        }
    }

    private func handleHello(_ data: [String: Any], password: String?) {
        var identifyPayload: [String: Any] = ["rpcVersion": 1]

        if let auth = data["authentication"] as? [String: Any],
           let salt = auth["salt"] as? String,
           let challenge = auth["challenge"] as? String {
            guard let password, !password.isEmpty else {
                state = .failed("OBS requires a password, but none was provided.")
                AppLogger.shared.log("OBS requires authentication but no password was set.", level: .error)
                disconnect()
                return
            }
            identifyPayload["authentication"] = computeAuthString(password: password, salt: salt, challenge: challenge)
        }

        send(op: 1, data: identifyPayload)
    }

    private func computeAuthString(password: String, salt: String, challenge: String) -> String {
        let secretHash = SHA256.hash(data: Data((password + salt).utf8))
        let secretBase64 = Data(secretHash).base64EncodedString()
        let authHash = SHA256.hash(data: Data((secretBase64 + challenge).utf8))
        return Data(authHash).base64EncodedString()
    }

    private func send(op: Int, data: [String: Any]) {
        let payload: [String: Any] = ["op": op, "d": data]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        webSocketTask?.send(.string(jsonString)) { error in
            if let error {
                AppLogger.shared.log("Failed to send to OBS: \(error.localizedDescription)", level: .error)
            }
        }
    }
}
