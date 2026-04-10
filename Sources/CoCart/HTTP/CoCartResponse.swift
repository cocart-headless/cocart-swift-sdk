import Foundation

public struct CoCartResponse {
    private let data: [String: Any]
    private let headers: [String: String]
    public let statusCode: Int

    init(data: [String: Any], headers: [String: String], statusCode: Int) {
        self.data = data
        self.headers = headers
        self.statusCode = statusCode
    }

    // MARK: - Dot-notation access

    public func get(_ path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any? = data
        for part in parts {
            if let dict = current as? [String: Any] {
                current = dict[part]
            } else if let array = current as? [Any], let idx = Int(part), idx < array.count {
                current = array[idx]
            } else {
                return nil
            }
        }
        return current
    }

    public func has(_ path: String) -> Bool { get(path) != nil }

    // MARK: - Typed convenience getters

    public func getString(_ path: String) -> String? { get(path) as? String }
    public func getInt(_ path: String) -> Int? { get(path) as? Int }
    public func getDouble(_ path: String) -> Double? { get(path) as? Double }
    public func getBool(_ path: String) -> Bool? { get(path) as? Bool }

    public func getItems() -> [[String: Any]] { get("items") as? [[String: Any]] ?? [] }
    public func getTotals() -> [String: Any] { get("totals") as? [String: Any] ?? [:] }
    public func getItemCount() -> Int { get("items_count") as? Int ?? 0 }
    public func getCartKey() -> String? { headers["cart-key"] ?? getString("cart_key") }
    public func getCartHash() -> String? { getString("cart_hash") }
    public func getNotices() -> [[String: Any]] { get("notices") as? [[String: Any]] ?? [] }
    public func getCurrency() -> [String: Any]? { get("currency") as? [String: Any] }
    public func getCacheStatus() -> String? { headers["cocart-cache"] }
    public func isNotModified() -> Bool { statusCode == 304 }

    public func toJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
    }

    public func toDictionary() -> [String: Any] { data }

    // MARK: - Codable decoding

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: self.data)
        return try JSONDecoder().decode(type, from: data)
    }
}
