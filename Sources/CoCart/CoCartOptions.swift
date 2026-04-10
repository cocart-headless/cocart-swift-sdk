import Foundation

public struct CoCartOptions {
    public var cartKey: String?
    public var storageKey: String

    public var username: String?
    public var password: String?

    public var jwtToken: String?
    public var jwtRefreshToken: String?

    public var consumerKey: String?
    public var consumerSecret: String?

    public var timeout: TimeInterval
    public var maxRetries: Int

    public var restPrefix: String
    public var namespace: String

    public var mainPlugin: MainPlugin

    public var authHeaderName: String

    public var storage: CoCartStorage?

    public var extraHeaders: [String: String]
    public var etag: Bool
    public var debug: Bool

    public enum MainPlugin {
        case basic, legacy
    }

    public init(
        cartKey: String? = nil,
        storageKey: String = "cocart_cart_key",
        username: String? = nil,
        password: String? = nil,
        jwtToken: String? = nil,
        jwtRefreshToken: String? = nil,
        consumerKey: String? = nil,
        consumerSecret: String? = nil,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        restPrefix: String = "wp-json",
        namespace: String = "cocart",
        mainPlugin: MainPlugin = .basic,
        authHeaderName: String = "Authorization",
        storage: CoCartStorage? = nil,
        extraHeaders: [String: String] = [:],
        etag: Bool = true,
        debug: Bool = false
    ) {
        self.cartKey = cartKey
        self.storageKey = storageKey
        self.username = username
        self.password = password
        self.jwtToken = jwtToken
        self.jwtRefreshToken = jwtRefreshToken
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.restPrefix = restPrefix
        self.namespace = namespace
        self.mainPlugin = mainPlugin
        self.authHeaderName = authHeaderName
        self.storage = storage
        self.extraHeaders = extraHeaders
        self.etag = etag
        self.debug = debug
    }
}
