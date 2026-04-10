import XCTest
@testable import CoCart

final class CurrencyFormatterTests: XCTestCase {

    private let usdCurrency: [String: Any] = [
        "currency_symbol": "$",
        "currency_symbol_position": "left",
        "currency_minor_unit": 2,
        "currency_decimal_separator": ".",
        "currency_thousand_separator": ","
    ]

    private let eurCurrency: [String: Any] = [
        "currency_symbol": "\u{20AC}",
        "currency_symbol_position": "right",
        "currency_minor_unit": 2,
        "currency_decimal_separator": ",",
        "currency_thousand_separator": "."
    ]

    func testFormatUSD() {
        let fmt = CurrencyFormatter()
        XCTAssertEqual(fmt.format(4599, currency: usdCurrency), "$45.99")
    }

    func testFormatEUR() {
        let fmt = CurrencyFormatter()
        let result = fmt.format(4599, currency: eurCurrency)
        XCTAssertTrue(result.hasSuffix("\u{20AC}"))
    }

    func testFormatDecimal() {
        let fmt = CurrencyFormatter()
        XCTAssertEqual(fmt.formatDecimal(4599, currency: usdCurrency), "45.99")
    }

    func testFormatZero() {
        let fmt = CurrencyFormatter()
        XCTAssertEqual(fmt.format(0, currency: usdCurrency), "$0.00")
    }

    func testFormatLargeAmount() {
        let fmt = CurrencyFormatter()
        let result = fmt.format(123456, currency: usdCurrency)
        XCTAssertEqual(result, "$1,234.56")
    }
}
