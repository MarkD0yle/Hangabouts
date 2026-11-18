import Foundation
import Network

/// A Claude Code hook event, as received over HTTP.
struct HookEvent {
    let name: String
    let payload: [String: Any]
    let receivedAt: Date
}

/// Tiny HTTP server for Claude Code's `http` hooks. Loopback only.
///
/// It accepts `POST /hooks/<EventName>` and always answers `200 {}`.
/// It never returns a decision: for `PermissionRequest` that would approve or deny the prompt.
/// Everything runs on the main queue, so events reach the state machine on the main thread.
@MainActor
final class HookServer {
    static let port: UInt16 = 7788
    static let maxBodyBytes = 5 * 1024 * 1024
    private static let maxHeaderBytes = 64 * 1024
    private static let connectionTimeout: TimeInterval = 10

    enum Status: Equatable {
        case starting
        case listening
        case portInUse
        case failed(String)
    }

    private(set) var status: Status = .starting {
        didSet { if status != oldValue { onStatusChanged?(status) } }
    }

    var onEvent: ((HookEvent) -> Void)?
    var onStatusChanged: ((Status) -> Void)?
    /// For problems worth a line in the console (bad requests, listener errors).
    var onLog: ((String) -> Void)?

    private var listener: NWListener?

    func start() {
        let parameters = NWParameters.tcp
        // Bind to 127.0.0.1 only. Never 0.0.0.0: hook payloads hold paths and tool inputs.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: HookServer.port)!)
        parameters.acceptLocalOnly = true

        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.listenerStateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = HookServer.isAddressInUse(error) ? .portInUse : .failed(error.localizedDescription)
            onLog?("Hook server could not start: \(error)")
        }
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = .listening
            onLog?("Hook server listening on 127.0.0.1:\(HookServer.port)")
        case .failed(let error), .waiting(let error):
            status = HookServer.isAddressInUse(error) ? .portInUse : .failed(error.localizedDescription)
            onLog?("Hook server stopped: \(error)")
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    private static func isAddressInUse(_ error: Error) -> Bool {
        if let error = error as? NWError, case .posix(let code) = error { return code == .EADDRINUSE }
        return false
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        // Don't let a stalled client hold a connection open for ever.
        DispatchQueue.main.asyncAfter(deadline: .now() + HookServer.connectionTimeout) { [weak connection] in
            connection?.cancel()
        }
        read(connection, buffer: Data())
    }

    /// Reads until the headers are complete, then exactly Content-Length bytes of body.
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }

                switch self.parse(buffer) {
                case .needMore:
                    if error != nil || isComplete {
                        connection.cancel() // the client went away mid-request
                    } else {
                        self.read(connection, buffer: buffer)
                    }
                case .reject(let code, let reason):
                    self.onLog?("Hook server: \(code) \(reason)")
                    self.respond(connection, status: "\(code) \(reason)", body: "")
                case .event(let name, let body):
                    // Answer first, so Claude Code never waits on us.
                    self.respond(connection, status: "200 OK", body: "{}")
                    self.deliver(name: name, body: body)
                }
            }
        }
    }

    private enum Parsed {
        case needMore
        case reject(Int, String)
        case event(name: String, body: Data)
    }

    private func parse(_ buffer: Data) -> Parsed {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > HookServer.maxHeaderBytes ? .reject(431, "Request Header Fields Too Large") : .needMore
        }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .reject(400, "Bad Request")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .reject(400, "Bad Request") }

        // Only POST /hooks/<EventName>. Anything else is a 404.
        let path = requestLine[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard requestLine[0] == "POST", parts.count == 3, parts[0].isEmpty, parts[1] == "hooks",
              !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return .reject(404, "Not Found")
        }

        var contentLength = 0
        for line in lines {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            guard let value = Int(pair[1].trimmingCharacters(in: .whitespaces)), value >= 0 else { return .reject(400, "Bad Request") }
            contentLength = value
        }
        guard contentLength <= HookServer.maxBodyBytes else { return .reject(413, "Payload Too Large") }

        let bodyStart = headerEnd.upperBound
        guard buffer.endIndex - bodyStart >= contentLength else { return .needMore }
        return .event(name: String(parts[2]), body: buffer.subdata(in: bodyStart..<(bodyStart + contentLength)))
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func deliver(name: String, body: Data) {
        // A body that isn't a JSON object still counts as an event: log it, with an empty payload.
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if payload == nil { onLog?("Hook server: \(name) had no JSON object body") }
        onEvent?(HookEvent(name: name, payload: payload ?? [:], receivedAt: Date()))
    }
}
