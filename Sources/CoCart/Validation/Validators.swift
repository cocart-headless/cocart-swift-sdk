import Foundation

public func validateProductID(_ id: Int) throws {
    guard id > 0 else {
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
