import Foundation

public struct CurrencyFormatter {
    public init() {}

    public func format(_ amount: Int, currency: [String: Any]) -> String {
        let decimals = currency["currency_minor_unit"] as? Int ?? 2
        let symbol = currency["currency_symbol"] as? String ?? ""
        let position = currency["currency_symbol_position"] as? String ?? "left"
        let decSep = currency["currency_decimal_separator"] as? String ?? "."
        let thouSep = currency["currency_thousand_separator"] as? String ?? ","

        let value = Double(amount) / pow(10.0, Double(decimals))
        let formatted = formatNumber(value, decimals: decimals, decSep: decSep, thouSep: thouSep)
        return position == "left" ? "\(symbol)\(formatted)" : "\(formatted)\(symbol)"
    }

    public func formatDecimal(_ amount: Int, currency: [String: Any]) -> String {
        let decimals = currency["currency_minor_unit"] as? Int ?? 2
        let value = Double(amount) / pow(10.0, Double(decimals))
        return String(format: "%.\(decimals)f", value)
    }

    private func formatNumber(_ value: Double, decimals: Int,
                              decSep: String, thouSep: String) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.groupingSeparator = thouSep
        formatter.decimalSeparator = decSep
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
