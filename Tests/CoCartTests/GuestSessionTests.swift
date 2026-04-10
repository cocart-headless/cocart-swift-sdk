import XCTest
@testable import CoCart

final class GuestSessionTests: XCTestCase {

    func testMemoryStorageReadWrite() async throws {
        let storage = MemoryStorage()
        try await storage.write("key", value: "value")
        let result = try await storage.read("key")
        XCTAssertEqual(result, "value")
    }

    func testMemoryStorageDelete() async throws {
        let storage = MemoryStorage()
        try await storage.write("key", value: "value")
        try await storage.delete("key")
        let result = try await storage.read("key")
        XCTAssertNil(result)
    }

    func testMemoryStorageReadMissing() async throws {
        let storage = MemoryStorage()
        let result = try await storage.read("nonexistent")
        XCTAssertNil(result)
    }

    func testMemoryStorageOverwrite() async throws {
        let storage = MemoryStorage()
        try await storage.write("key", value: "first")
        try await storage.write("key", value: "second")
        let result = try await storage.read("key")
        XCTAssertEqual(result, "second")
    }

    func testClientRestoreSession() async throws {
        let storage = MemoryStorage()
        try await storage.write("cocart_cart_key", value: "restored_key")
        let client = CoCart("https://example.com", options: CoCartOptions(storage: storage))
        try await client.restoreSession()
        XCTAssertEqual(client.cartKey, "restored_key")
    }

    func testClientClearSession() async throws {
        let storage = MemoryStorage()
        let client = CoCart("https://example.com", options: CoCartOptions(cartKey: "key123", storage: storage))
        try await client.clearSession()
        XCTAssertNil(client.cartKey)
        XCTAssertTrue(client.isGuest)
    }
}
