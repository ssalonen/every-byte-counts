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
public final class FileDataStore: DataStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(AppState.self, from: data) else {
            // First run or unreadable file → fresh state.
            return AppState()
        }
        return state
    }

    public func save(_ state: AppState) {
        guard let data = try? encoder.encode(state) else { return }
        // Atomic write so a widget refresh that overlaps an app write can never
        // observe a half-written file.
        try? data.write(to: url, options: .atomic)
    }
}
