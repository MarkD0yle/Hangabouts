import Foundation

/// State of one Claude Code session. Raw values go in the event log as `stateAfter`.
enum SessionState: String {
    case working
    case done
    case needsYou
    case failed

    /// What the menu calls it.
    var menuLabel: String {
        switch self {
        case .working: return "Digging"
        case .done: return "Done"
        case .needsYou: return "Needs you"
        case .failed: return "Failed"
        }
    }

    /// Failed > Needs you > Done > Working.
    var priority: Int {
        switch self {
        case .working: return 0
        case .done: return 1
        case .needsYou: return 2
        case .failed: return 3
        }
    }
}

struct Session {
    let id: String
    var state: SessionState
    var reason: String?
    /// Needs you because auto mode blocked a tool call. Unlike a prompt, the end of the turn doesn't answer it.
    var blocked = false
    var cwd: String?
    /// When the session entered its current state. Picks the oldest when several need you.
    var since: Date

    /// Last part of `cwd`, e.g. "sandbox-002".
    var folderName: String {
        guard let cwd, !cwd.isEmpty else { return "Unknown folder" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// Which hook events may put a session into Needs you. Spec 001 decides which wins.
enum NeedsYouSource: String, CaseIterable {
    case permissionRequest
    case notification
    case both

    var menuLabel: String {
        switch self {
        case .permissionRequest: return "PermissionRequest only"
        case .notification: return "Notification only"
        case .both: return "Both"
        }
    }
}

/// Per-session state machine (Spec 002, "Events to state"). Main thread only.
@MainActor
final class SessionStore {
    static let needsYouSourceKey = "needsYouSource"
    static let debugSessionID = "debug-simulated"
    private static let questionTool = "AskUserQuestion"
    private static let questionReason = "Has a question"

    private(set) var sessions: [String: Session] = [:]

    var needsYouSource: NeedsYouSource {
        didSet { UserDefaults.standard.set(needsYouSource.rawValue, forKey: SessionStore.needsYouSourceKey) }
    }

    /// Called after any change to the sessions.
    var onChange: (() -> Void)?

    init() {
        let saved = UserDefaults.standard.string(forKey: SessionStore.needsYouSourceKey)
        needsYouSource = saved.flatMap(NeedsYouSource.init(rawValue:)) ?? .both
    }

    // MARK: - Reading

    /// Sessions for the menu: oldest state first, so the list doesn't jump about.
    var ordered: [Session] {
        sessions.values.sorted { ($0.since, $0.id) < ($1.since, $1.id) }
    }

    /// The session Snuffler speaks for: highest priority, then the one waiting longest.
    var top: Session? {
        sessions.values.max { a, b in
            a.state.priority != b.state.priority ? a.state.priority < b.state.priority : a.since > b.since
        }
    }

    // MARK: - Events

    /// Applies one hook event. Returns the session's state afterwards, or nil if it has none.
    @discardableResult
    func apply(_ event: HookEvent) -> SessionState? {
        // No session id: nothing to key the state on. The caller still logs the event.
        guard let id = event.payload["session_id"] as? String, !id.isEmpty else { return nil }

        if event.name == "SessionEnd" {
            if sessions.removeValue(forKey: id) != nil { onChange?() }
            return nil
        }

        let before = sessions[id]
        var session = before ?? Session(id: id, state: .working, reason: nil, cwd: nil, since: event.receivedAt)
        if let cwd = event.payload["cwd"] as? String, !cwd.isEmpty { session.cwd = cwd }

        var next: (state: SessionState, reason: String?)? = nil
        var blocked = false
        let tool = event.payload["tool_name"] as? String
        switch event.name {
        case "SessionStart", "UserPromptSubmit":
            // A new prompt or session is also the only thing that clears Failed.
            next = (.working, nil)

        case "PreToolUse" where tool == SessionStore.questionTool:
            // Claude is asking you something. In auto mode this is the main way a session waits on you.
            if session.state != .failed { next = (.needsYou, SessionStore.questionReason) }

        case "PreToolUse", "PostToolUse":
            // Work is moving, so a prompt or question was answered, or Claude found a way round a block.
            // Failed stays until the next prompt.
            if session.state != .failed { next = (.working, nil) }

        case "PermissionRequest":
            if tool == SessionStore.questionTool {
                next = (.needsYou, SessionStore.questionReason) // a question, whatever the source switch says
            } else if needsYouSource != .notification {
                next = (.needsYou, tool.map { "Wants to run \($0)" })
            }

        case "PermissionDenied":
            // Auto mode blocked a tool call. Nobody was asked, so this is the only sign of it.
            if session.state != .failed {
                next = (.needsYou, "Auto mode blocked \(tool ?? "a tool call")")
                blocked = true
            }

        case "Notification":
            switch event.payload["notification_type"] as? String {
            case "permission_prompt":
                // PermissionRequest usually got here first, with a better reason. Keep it.
                if needsYouSource != .permissionRequest, session.state != .needsYou {
                    next = (.needsYou, event.payload["message"] as? String)
                }
            case "idle_prompt":
                // Fires about 60 s after every finished turn. It means "finished and waiting", not "blocked".
                if session.state == .working { next = (.done, nil) }
            default:
                break
            }

        case "Stop":
            // The turn ended, so any prompt was answered. Failed stays until the next prompt.
            // So does a block: if Claude stopped without getting round it, the session still needs you.
            if session.state != .failed, !(session.state == .needsYou && session.blocked) { next = (.done, nil) }

        case "StopFailure":
            next = (.failed, SessionStore.failureReason(event.payload))

        default:
            break // an event we don't map; a new session still shows up as Working
        }

        if let next {
            if next.state != session.state { session.since = event.receivedAt }
            session.state = next.state
            session.reason = next.reason
            session.blocked = blocked
        }

        sessions[id] = session
        if before == nil || before?.state != session.state || before?.reason != session.reason || before?.cwd != session.cwd {
            onChange?()
        }
        return session.state
    }

    /// `StopFailure` puts the cause in `error` (e.g. "rate_limit"), with optional `error_details`.
    private static func failureReason(_ payload: [String: Any]) -> String? {
        let error = (payload["error"] as? String).map { $0.replacingOccurrences(of: "_", with: " ") }
        let details = payload["error_details"] as? String
        switch (error, details) {
        case let (error?, details?) where !details.isEmpty: return "\(error): \(details)"
        case let (error?, _): return error
        case let (nil, details?): return details
        default: return nil
        }
    }

    // MARK: - Debug menu

    /// Debug › Simulate Needs you. Works with no Claude Code session.
    /// Returns false if the debug session already needed you, so the caller can nudge instead.
    func simulateNeedsYou() -> Bool {
        if sessions[SessionStore.debugSessionID]?.state == .needsYou { return false }
        sessions[SessionStore.debugSessionID] = Session(
            id: SessionStore.debugSessionID, state: .needsYou, reason: "Simulated", cwd: "debug", since: Date()
        )
        onChange?()
        return true
    }

    /// Debug › Clear all. Forgets every session, real ones too. They come back on their next event.
    func clearAll() {
        guard !sessions.isEmpty else { return }
        sessions.removeAll()
        onChange?()
    }
}
