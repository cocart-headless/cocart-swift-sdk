import Foundation

private let numericStringPattern = #"^\s*-?\d+(\.\d+)?\s*$"#

public func validateProductID(_ id: Int) throws {
    guard id > 0 else {
        throw CoCartError.validation("Product ID must be a positive integer")
    }
}

/// Validates a product ID given as a string, mirroring the server's own
/// resolution rules.
///
/// A string containing only a number must represent a positive integer. A
/// non-numeric string is treated as a potential SKU and passed through
/// untouched — the server resolves a non-numeric ID before falling back to a 404.
/// This SDK can't verify a SKU exists without a network request, so it only rejects
/// input that's certain to be invalid: empty, or numeric but not a positive integer.
public func validateProductID(_ id: String) throws {
    let trimmed = id.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
        throw CoCartError.validation("Product ID must be a positive integer")
    }
    guard trimmed.range(of: numericStringPattern, options: .regularExpression) != nil else {
        return // Non-numeric string — treat as a SKU; the server resolves it.
    }
    guard let value = Double(trimmed), value >= 1, value.truncatingRemainder(dividingBy: 1) == 0 else {
        throw CoCartError.validation("Product ID must be a positive integer")
    }
}

public func validateQuantity(_ quantity: Double) throws {
    guard quantity > 0 else {
        throw CoCartError.validation("Quantity must be a positive number")
    }
}

public func validateEmail(_ email: String) throws {
    let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
    guard email.range(of: pattern, options: .regularExpression) != nil else {
        throw CoCartError.validation("Invalid email address")
    }
}
