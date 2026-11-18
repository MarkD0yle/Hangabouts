import Foundation

/// Appends one JSON line per hook event to
/// `~/Library/Application Support/Hangabouts/events.jsonl`.
/// Same shape as the Spec 001 listener (`event`, `receivedAt`, `receivedAtMs`, `payload`), plus `stateAfter`.
/// The file holds paths and tool inputs. It stays out of the repo.
@MainActor
final class EventLog {
    let url: URL
    private var handle: FileHandle?
    private let timestamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var onLog: ((String) -> Void)?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("Hangabouts", isDirectory: true).appendingPathComponent("events.jsonl")
    }

    /// Creates the folder and file if needed. Safe to call again.
    func open() {
        guard handle == nil else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            self.handle = handle
        } catch {
            onLog?("Event log unavailable: \(error.localizedDescription)")
        }
    }

    /// `stateAfter` is the session's state once the event was applied, or nil if it has none.
    func append(_ event: HookEvent, stateAfter: String?) {
        open()
        guard let handle else { return }
        let line: [String: Any] = [
            "event": event.name,
            "receivedAt": timestamps.string(from: event.receivedAt),
            "receivedAtMs": Int((event.receivedAt.timeIntervalSince1970 * 1000).rounded()),
            "payload": event.payload,
            "stateAfter": stateAfter ?? NSNull(),
        ]
        do {
            var data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
            data.append(0x0A)
            try handle.write(contentsOf: data)
        } catch {
            onLog?("Event log write failed: \(error.localizedDescription)")
        }
    }
}
