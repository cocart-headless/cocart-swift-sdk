import Foundation

public actor MemoryStorage: CoCartStorage {
    private var store: [String: String] = [:]

    public init() {}

    public func read(_ key: String) async throws -> String? {
        store[key]
    }

    public func write(_ key: String, value: String) async throws {
        store[key] = value
    }

    public func delete(_ key: String) async throws {
        store.removeValue(forKey: key)
    }
}
