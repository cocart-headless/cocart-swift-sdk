import Foundation

public enum CoCartError: Error, LocalizedError {
    case auth(String, code: String?)
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
