import XCTest
@testable import CoCart

final class ValidatorsTests: XCTestCase {

    func testValidateProductIDPositive() {
        XCTAssertNoThrow(try validateProductID(1))
        XCTAssertNoThrow(try validateProductID(999))
    }

    func testValidateProductIDZeroThrows() {
        XCTAssertThrowsError(try validateProductID(0))
    }

    func testValidateProductIDNegativeThrows() {
        XCTAssertThrowsError(try validateProductID(-1))
    }

    func testValidateQuantityPositive() {
        XCTAssertNoThrow(try validateQuantity(1.0))
        XCTAssertNoThrow(try validateQuantity(0.5))
    }

    func testValidateQuantityZeroThrows() {
        XCTAssertThrowsError(try validateQuantity(0))
    }

    func testValidateQuantityNegativeThrows() {
        XCTAssertThrowsError(try validateQuantity(-1))
    }

    func testValidateEmailValid() {
        XCTAssertNoThrow(try validateEmail("test@example.com"))
        XCTAssertNoThrow(try validateEmail("user+tag@domain.co"))
    }

    func testValidateEmailInvalid() {
        XCTAssertThrowsError(try validateEmail("not-an-email"))
        XCTAssertThrowsError(try validateEmail("@missing-local.com"))
        XCTAssertThrowsError(try validateEmail("missing-at.com"))
    }
}
