import Foundation

public final class MemoryStorage: CoCartStorage, @unchecked Sendable {
    private var store: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ key: String) async throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    public func write(_ key: String, value: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        store[key] = value
    }

    public func delete(_ key: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}
