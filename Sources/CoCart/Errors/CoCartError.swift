import Foundation

public enum CoCartError: Error, LocalizedError {
    case auth(String, code: String?)
    /// Thrown by `JWTResource.login()` when the server requires a 2FA code to complete login.
    ///
    /// Catch this error, read `availableProviders` / `defaultProvider` / `emailSent`,
    /// prompt the user for their code, then call `JWTResource.verifyTwoFactor()`.
    case twoFactorRequired(String, availableProviders: [String], defaultProvider: String?, emailSent: Bool)
    case forbidden(String)
    case notFound(String)
    case rateLimited(retryAfter: Int?)
    /// Any other API error. `data` is the full response body.
    case api(String, statusCode: Int, code: String?, data: [String: Any])
    case network(String)
    case validation(String)
    case version(String)

    public var errorDescription: String? {
        switch self {
        case .auth(let msg, _): return "Authentication error: \(msg)"
        case .twoFactorRequired(let msg, _, _, _): return "Two-factor authentication required: \(msg)"
        case .forbidden(let msg): return "Forbidden: \(msg)"
        case .notFound(let msg): return "Not found: \(msg)"
        case .rateLimited(let after): return "Rate limited\(after.map { ". Retry after \($0)s" } ?? "")"
        case .api(let msg, let code, _, _): return "API error \(code): \(msg)"
        case .network(let msg): return "Network error: \(msg)"
        case .validation(let msg): return "Validation error: \(msg)"
        case .version(let msg): return "Version error: \(msg)"
        }
    }

    /// The API error code, e.g. `cocart_item_not_in_cart`, when the server sent one.
    public var errorCode: String? {
        switch self {
        case .auth(_, let code): return code
        case .twoFactorRequired: return "cocart_2fa_required"
        case .api(_, _, let code, _): return code
        default: return nil
        }
    }

    /// The cart sent with the error, when CoCart sends one: `cocart_item_not_in_cart`
    /// (an item key that isn't in the cart) carries the cart as it is now, so you can
    /// show it without another request. `nil` otherwise.
    public func getCart() -> [String: Any]? {
        guard case .api(_, _, _, let data) = self,
              let details = data["data"] as? [String: Any],
              let cart = details["cart"] as? [String: Any],
              !cart.isEmpty else { return nil }
        return cart
    }

    /// Every field at fault, by path (e.g. `billing.postcode`), with its message: CoCart Plus
    /// checks a whole form at once (`data.fields`). Empty when the error isn't about fields.
    public var fields: [String: String] {
        guard let fields = details?["fields"] as? [String: Any] else { return [:] }
        return fields.compactMapValues { $0 as? String }
    }

    /// The first field at fault, as a path such as `billing.postcode` (`data.field`), or `nil`.
    public var field: String? {
        guard let field = details?["field"] as? String, !field.isEmpty else { return nil }
        return field
    }

    /// The underlying plugin's own reason, when there is one (`data.reason`), or `nil`.
    public var reason: String? {
        guard let reason = details?["reason"] as? String, !reason.isEmpty else { return nil }
        return reason
    }

    /// The error's `data` object, for an API error.
    private var details: [String: Any]? {
        guard case .api(_, _, _, let data) = self else { return nil }
        return data["data"] as? [String: Any]
    }
}
