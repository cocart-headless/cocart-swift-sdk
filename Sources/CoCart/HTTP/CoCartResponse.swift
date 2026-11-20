import Foundation

/// The `RateLimit-*` headers: `limit` requests per window, `remaining` in this window,
/// `reset` (the Unix time the window resets) and `retryAfter` (seconds to wait after a 429).
public struct RateLimitInfo: Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let reset: Int?
    public let retryAfter: Int?
}

public struct CoCartResponse {
    private let data: [String: Any]
    /// The body when the route answered with a list (categories, tags, attributes, reviews, variations).
    private let list: [Any]?
    private let headers: [String: String]
    public let statusCode: Int
    /// The body as received, for the order of an object's keys (a dictionary has none).
    private let raw: Data?

    init(data: [String: Any], headers: [String: String], statusCode: Int, list: [Any]? = nil, raw: Data? = nil) {
        self.data = data
        self.list = list
        self.raw = raw
        // Header names are case-insensitive: keep them lowercase.
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.statusCode = statusCode
    }

    // MARK: - Dot-notation access

    /// Dot-notation access: `get("totals.total")`, `get("items.0.name")`; a list body
    /// starts at an index: `get("0.name")`.
    public func get(_ path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any? = list ?? data
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

    /// A response header, ignoring the name's case.
    public func getHeader(_ name: String) -> String? { headers[name.lowercased()] }

    // MARK: - Typed convenience getters

    public func getString(_ path: String) -> String? { get(path) as? String }
    public func getInt(_ path: String) -> Int? { get(path) as? Int }
    public func getDouble(_ path: String) -> Double? { get(path) as? Double }
    public func getBool(_ path: String) -> Bool? { get(path) as? Bool }

    public func getItems() -> [[String: Any]] { get("items") as? [[String: Any]] ?? [] }
    public func getTotals() -> [String: Any] { get("totals") as? [String: Any] ?? [:] }
    public func getItemCount() -> Int { get("item_count") as? Int ?? 0 }
    public func getCartKey() -> String? { headers["cart-key"] ?? getString("cart_key") }
    public func getCartHash() -> String? { getString("cart_hash") }

    /// The notices, keyed by type (`success`, `error`, `notice`, `info`), each a list of
    /// messages, e.g. `["success": ["“Beanie” has been added to your cart."]]`. Empty when
    /// there are none (CoCart Starter 5 sends `{}`, CoCart 4.x `[]`).
    public func getNotices() -> [String: [String]] {
        guard let notices = get("notices") as? [String: Any] else { return [:] }
        return notices.mapValues { ($0 as? [Any])?.map { "\($0)" } ?? [] }
    }

    public func getCurrency() -> [String: Any]? { get("currency") as? [String: Any] }

    /// The shipping packages, as a list. Each package has its `rates` keyed by rate ID,
    /// and `chosen_method`. CoCart sends the packages keyed by package ID under
    /// `shipping.packages`; see `getShipping()` for the whole field. The packages are in
    /// the order of their `index`.
    public func getShippingMethods() -> [[String: Any]] {
        if let list = get("shipping") as? [[String: Any]] { return list }
        let packages = valuesOf(get("shipping.packages"))
        return packages.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
    }

    /// The cart's whole `shipping` field: `total_packages`, `show_package_details`,
    /// `has_calculated_shipping` and `packages` (keyed by package ID). `nil` when the
    /// response has none.
    public func getShipping() -> [String: Any]? { get("shipping") as? [String: Any] }

    /// The cart's fees, as a list. The cart keys fees by fee ID (`{}` when there are none;
    /// `[]` from CoCart 4.x).
    public func getFees() -> [[String: Any]] { valuesOf(get("fees")) }

    /// The cart's `extensions`: data plugins add to the cart, such as subscription
    /// `recurring_totals` (see docs/extension-data.md). Empty when there is none.
    public func getExtensions() -> [String: Any] { get("extensions") as? [String: Any] ?? [:] }

    /// The `RateLimit-*` headers CoCart Plus sends when rate limiting is on. A value is
    /// `nil` when its header wasn't sent.
    public func getRateLimit() -> RateLimitInfo {
        func number(_ name: String) -> Int? {
            guard let value = headers[name]?.trimmingCharacters(in: .whitespaces),
                  let number = Double(value), number.isFinite else { return nil }
            return Int(number)
        }
        return RateLimitInfo(
            limit: number("ratelimit-limit"),
            remaining: number("ratelimit-remaining"),
            reset: number("ratelimit-reset"),
            retryAfter: number("ratelimit-retry-after")
        )
    }

    /// Get cart tax lines, normalized to a flat array — one entry per tax
    /// rate when the store's tax display setting is itemized.
    ///
    /// CoCart Starter 5.0+ already returns this shape as an array. The
    /// community CoCart plugin (and older Starter versions) instead return
    /// an object keyed by the tax rate code, e.g. `{ "US-US-1": { name,
    /// price } }` — that legacy shape is detected and converted here so
    /// callers never need to branch on which plugin/version they're talking to.
    public func getTaxes() -> [[String: Any]] {
        guard let raw = get("taxes") else { return [] }
        if let array = raw as? [[String: Any]] {
            return array
        }
        guard let legacy = raw as? [String: Any] else { return [] }
        return legacy.map { key, value -> [String: Any] in
            let tax = value as? [String: Any] ?? [:]
            var entry: [String: Any] = ["key": key]
            if let name = tax["name"] { entry["name"] = name }
            if let price = tax["price"] { entry["price"] = price }
            return entry
        }
    }

    /// Check if the cart has any tax lines.
    public func hasTaxes() -> Bool { !getTaxes().isEmpty }

    public func getCacheStatus() -> String? { headers["cocart-cache"] }
    public func isNotModified() -> Bool { statusCode == 304 }

    public func toJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: list ?? data, options: .prettyPrinted)
    }

    /// The body as a dictionary; empty when the route answered with a list (see `toArray()`).
    public func toDictionary() -> [String: Any] { data }

    /// The body's top-level keys in the order the server sent them, then any others sorted.
    func orderedKeys() -> [String] {
        let sent = raw.map(Self.topLevelKeys) ?? []
        return sent.filter { data[$0] != nil } + data.keys.filter { !sent.contains($0) }.sorted()
    }

    /// A JSON object's top-level keys, in order.
    private static func topLevelKeys(_ json: Data) -> [String] {
        let bytes = [UInt8](json)
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        var keys: [String] = []
        var depth = 0
        var expectKey = false
        var i = 0
        while i < bytes.count {
            let c = bytes[i]
            if c == quote {
                var j = i + 1
                var escaped = false
                while j < bytes.count {
                    if escaped { escaped = false } else if bytes[j] == backslash { escaped = true } else if bytes[j] == quote { break }
                    j += 1
                }
                if depth == 1 && expectKey,
                   let key = try? JSONSerialization.jsonObject(with: Data(bytes[i...min(j, bytes.count - 1)]), options: [.fragmentsAllowed]) as? String {
                    keys.append(key)
                }
                expectKey = false
                i = j + 1
                continue
            }
            switch c {
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                expectKey = depth == 1 && c == UInt8(ascii: "{")
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
            case UInt8(ascii: ","):
                if depth == 1 { expectKey = true }
            default:
                break
            }
            i += 1
        }
        return keys
    }

    /// The body as an array, for routes that answer with one (categories, tags,
    /// attributes, reviews, variations); empty otherwise.
    public func toArray() -> [Any] { list ?? [] }

    // MARK: - Codable decoding

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: list ?? self.data)
        return try JSONDecoder().decode(type, from: data)
    }

    /// The values of an object keyed by ID, or the elements of a list, as dictionaries.
    private func valuesOf(_ value: Any?) -> [[String: Any]] {
        if let list = value as? [Any] { return list.compactMap { $0 as? [String: Any] } }
        if let keyed = value as? [String: Any] { return keyed.values.compactMap { $0 as? [String: Any] } }
        return []
    }
}
