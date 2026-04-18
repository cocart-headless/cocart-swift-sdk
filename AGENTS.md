# CoCart Swift SDK

Official Swift SDK for the CoCart REST API.

- **Package:** `CoCart` (Swift Package Manager)
- **Version:** 1.0.0
- **Distribution:** Swift Package Manager (SPM)
- **Platforms:** iOS 17+, macOS 14+, watchOS 10+
- **License:** MIT
- **Zero external dependencies** — uses `URLSession` and `Security` framework

---

## Commands

```bash
swift package resolve                                            # resolve/install dependencies
swift build                                                      # build
swift build --configuration debug                               # debug build
swift test                                                       # run all tests
swift test --configuration debug                                 # debug test run
swift test --filter CoCartClientTests.testDefaultInit           # run a single test
```

---

## Tech Stack

| | |
|---|---|
| Language | Swift 5.10+ |
| Platforms | iOS 17+, macOS 14+, watchOS 10+ |
| Tests | XCTest (built-in) |
| HTTP | `URLSession` (standard library) |
| Storage | `Security` framework (Keychain) |
| Build | Swift Package Manager |
| External deps | none |

---

## Project Structure

```
Sources/CoCart/
  CoCart.swift               # main entry point, fluent setters, resource accessors
  CoCartOptions.swift        # CoCartOptions struct
  Auth/
    AuthManager.swift        # auth priority, cart key capture
  HTTP/
    HTTPClient.swift         # URLSession wrapper, retries, ETag, events
    CoCartResponse.swift     # Response wrapper with dot-notation access
  Resources/
    CartResource.swift
    ProductsResource.swift
    SessionsResource.swift
    JWTResource.swift
  Storage/
    CoCartStorage.swift      # protocol
    KeychainStorage.swift    # default (Keychain)
    MemoryStorage.swift      # for tests
  Errors/
    CoCartError.swift
  Utilities/
    CurrencyFormatter.swift
  Validation/
    Validators.swift
Tests/CoCartTests/
  CoCartClientTests.swift
  AuthManagerTests.swift
  GuestSessionTests.swift
  ResponseTests.swift
  ValidatorsTests.swift
  CurrencyFormatterTests.swift
  Mocks/
    MockURLSession.swift
```

---

## Code Style

- **File names:** `PascalCase.swift` (e.g., `AuthManager.swift`, `CartResource.swift`)
- **Classes / structs / enums / protocols:** `PascalCase`
- **Functions, methods, variables:** `camelCase`
- **MARK comments** for section organisation: `// MARK: - Init`, `// MARK: - Resources`
- `async throws` for all async methods
- `@discardableResult` on fluent setters that return `Self`
- No SwiftLint or SwiftFormat config — follow standard Swift conventions

---

## Git

- **Commit style:** Imperative, capital first letter — `Add X`, `Added X`, `Fix X`
- **Co-author footer:** `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`

---

## Testing

| | |
|---|---|
| Framework | XCTest |
| Location | `Tests/CoCartTests/` |
| File pattern | `*Tests.swift` |
| Class pattern | `final class FooTests: XCTestCase` |
| Method pattern | `func testSomething()` |
| Mocking | `MockURLSession` in `Tests/CoCartTests/Mocks/` |
| Coverage | not configured |

Run a specific test class: `swift test --filter CoCartClientTests`. Run a specific method: `swift test --filter CoCartClientTests.testDefaultInit`.
