import Foundation

/// Persistence boundary for the shared `AppState`. Synchronous and process-free
/// (design §4: "avoid anything that needs a running process") so the widget can
/// load, mutate and save during a brief timeline refresh.
public protocol DataStore: AnyObject {
    func load() -> AppState
    func save(_ state: AppState)
}

/// In-memory store for tests and previews.
public final class InMemoryDataStore: DataStore {
    private var state: AppState

    public init(_ state: AppState = AppState()) {
        self.state = state
    }

    public func load() -> AppState { state }
    public func save(_ state: AppState) { self.state = state }
}

/// JSON-file store living in the App Group container — the only place the app and
/// widget can see the same bytes.
///
/// Failure semantics matter here because callers (the `SamplingEngine`) do
/// load → mutate → save: a `load()` that papered over a transient read error by
/// returning defaults would get those defaults saved right back, permanently
/// wiping the user's plan and history. So the three failure modes are kept apart:
///
/// - **File missing** — genuine first run. Defaults are correct and saving is fine.
/// - **File exists but can't be read** — transient I/O failure, e.g. data
///   protection before the first unlock while a widget refresh samples. Defaults
///   are returned so the caller can render *something*, but `save(_:)` becomes a
///   no-op until a later load succeeds, so the real bytes are never clobbered.
/// - **File read but won't decode** — the bytes really are bad (corruption or a
///   schema from a newer build). The file is moved aside to `<name>.corrupt` so
///   nothing is destroyed, and the store starts fresh.
public final class FileDataStore: DataStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Set when the last `load()` found an existing file it could not read.
    /// While set, `save(_:)` refuses to write (see type docs).
    private var lastLoadWasUnreadable = false

    /// Where an undecodable file is preserved before starting fresh.
    public var corruptBackupURL: URL { url.appendingPathExtension("corrupt") }

    /// - Parameter url: file URL inside the shared App Group container, typically
    ///   `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`
    ///   plus a filename.
    public init(url: URL) {
        self.url = url
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> AppState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Genuine first run.
            lastLoadWasUnreadable = false
            return AppState()
        }
        guard let data = try? Data(contentsOf: url) else {
            // Exists but unreadable right now (e.g. device locked). Do NOT let
            // this session overwrite the real data with what we return here.
            lastLoadWasUnreadable = true
            return AppState()
        }
        lastLoadWasUnreadable = false
        guard let state = try? decoder.decode(AppState.self, from: data) else {
            // Bad bytes: keep them recoverable, then behave like a first run.
            let fm = FileManager.default
            try? fm.removeItem(at: corruptBackupURL)
            try? fm.moveItem(at: url, to: corruptBackupURL)
            return AppState()
        }
        return state
    }

    public func save(_ state: AppState) {
        guard !lastLoadWasUnreadable else { return }
        guard let data = try? encoder.encode(state) else { return }
        // Atomic write so a widget refresh that overlaps an app write can never
        // observe a half-written file. No file protection: the counters aren't
        // sensitive, and the widget must be able to sample before first unlock.
        try? data.write(to: url, options: writeOptions)
    }

    private var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .noFileProtection]
        #else
        return [.atomic]
        #endif
    }
}
