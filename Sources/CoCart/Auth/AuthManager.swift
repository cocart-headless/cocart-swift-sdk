import Foundation

public enum AuthMode {
    case guest, basicAuth, jwt, consumerKeys
}

final class AuthManager {
    private(set) var mode: AuthMode = .guest
    private(set) var cartKey: String?

    private var username: String?
    private var password: String?
    private var jwtToken: String?
    private var refreshToken: String?
    private var consumerKey: String?
    private var consumerSecret: String?

    private let options: CoCartOptions
    private let storage: CoCartStorage

    init(options: CoCartOptions, storage: CoCartStorage) {
        self.options = options
        self.storage = storage
        self.cartKey = options.cartKey
        self.consumerKey = options.consumerKey
        self.consumerSecret = options.consumerSecret

        if let token = options.jwtToken {
            jwtToken = token
            refreshToken = options.jwtRefreshToken
            mode = .jwt
        } else if options.username != nil {
            username = options.username
            password = options.password
            mode = .basicAuth
        } else if options.consumerKey != nil {
            mode = .consumerKeys
        }
    }

    var isAuthenticated: Bool { mode != .guest }
    var isGuest: Bool { mode == .guest }
    var activeJWTToken: String? { jwtToken }
    var activeRefreshToken: String? { refreshToken }

    func authorizationHeaderValue() -> String? {
        switch mode {
        case .jwt:
            guard let token = jwtToken else { return nil }
            return "Bearer \(token)"
        case .basicAuth:
            guard let u = username, let p = password else { return nil }
            let encoded = Data("\(u):\(p)".utf8).base64EncodedString()
            return "Basic \(encoded)"
        case .consumerKeys:
            guard let ck = consumerKey, let cs = consumerSecret else { return nil }
            let encoded = Data("\(ck):\(cs)".utf8).base64EncodedString()
            return "Basic \(encoded)"
        case .guest:
            return nil
        }
    }

    var guestCartKey: String? {
        mode == .guest ? cartKey : nil
    }

    func captureCartKey(from body: [String: Any], headers: [String: String]) {
        guard mode == .guest else { return }
        let key = body["cart_key"] as? String
            ?? headers["cart-key"]
            ?? headers["cocart-api-cart-key"]
        guard let key, key != cartKey else { return }
        cartKey = key
        Task { try? await storage.write(options.storageKey, value: key) }
    }

    func setBasicAuth(_ identifier: String, password: String) {
        username = identifier
        self.password = password
        jwtToken = nil
        refreshToken = nil
        mode = .basicAuth
    }

    func setJWTToken(_ token: String) {
        jwtToken = token
        username = nil
        password = nil
        mode = .jwt
    }

    func setRefreshToken(_ token: String) {
        refreshToken = token
    }

    func restoreSession() async throws {
        if cartKey == nil {
            cartKey = try await storage.read(options.storageKey)
        }
    }

    func clearSession() async throws {
        cartKey = nil
        jwtToken = nil
        refreshToken = nil
        username = nil
        password = nil
        mode = .guest
        try await storage.delete(options.storageKey)
    }
}
