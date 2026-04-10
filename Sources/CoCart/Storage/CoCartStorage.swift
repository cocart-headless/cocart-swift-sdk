import Foundation

public protocol CoCartStorage: Sendable {
    func read(_ key: String) async throws -> String?
    func write(_ key: String, value: String) async throws
    func delete(_ key: String) async throws
}
