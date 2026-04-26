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
    case api(String, statusCode: Int, code: String?)
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
        case .api(let msg, let code, _): return "API error \(code): \(msg)"
        case .network(let msg): return "Network error: \(msg)"
        case .validation(let msg): return "Validation error: \(msg)"
        case .version(let msg): return "Version error: \(msg)"
        }
    }
}
