# Error Handling

When something goes wrong — a product doesn't exist, the customer isn't logged in, or the server has a problem — the SDK throws an **error**. Errors are Swift `Error` types that describe what went wrong. You catch them using `do/catch` blocks (shown below).

## Error Types

The SDK uses a single `CoCartError` enum with cases for different error categories:

```text
CoCartError
├── .auth(String, code: String?)      — login/permission problems (401, 403)
├── .forbidden(String)                — insufficient permissions (403)
├── .notFound(String)                 — resource not found (404)
├── .rateLimited(retryAfter: Int?)    — too many requests (429)
├── .api(String, statusCode: Int, code: String?, data: [String: Any])  — other API errors, with the response body
├── .network(String)                  — connection/timeout failures
├── .validation(String)               — bad input (client-side)
└── .version(String)                  — method requires CoCart Starter
```

`CoCartError` conforms to `LocalizedError`, so you can use `error.localizedDescription` or `error.errorDescription` to get a human-readable message. `error.errorCode` gives the API error code (e.g. `cocart_item_not_in_cart`) when the server sent one, and `error.getCart()` the cart sent with the error (see [Item No Longer in the Cart](#item-no-longer-in-the-cart)).

CoCart Plus checks a whole form at once and says which fields are at fault (see [Fields at Fault](#fields-at-fault)):

| Property | Value |
|---|---|
| `fields` | `[String: String]`: every field at fault, by path (`billing.postcode`), with its message (`data.fields`). Empty when the error isn't about fields |
| `field` | `String?`: the first field at fault (`data.field`) |
| `reason` | `String?`: the underlying plugin's own reason, when there is one (`data.reason`) |

## Catching Errors

In Swift, `do/catch` lets you attempt an operation and handle any errors gracefully instead of crashing. Pattern matching on the error cases lets you respond differently to different problems:

```swift
import CoCart

do {
    let response = try await client.cart().addItem(999, quantity: 1)
} catch let error as CoCartError {
    switch error {
    case .validation(let message):
        // Bad input — product not found, out of stock, invalid quantity, etc.
        print("Validation Error: \(message)")

    case .auth(let message, let code):
        // 401 — invalid credentials, expired token
        print("Auth Error: \(message), code: \(code ?? "none")")

    case .forbidden(let message):
        // 403 — insufficient permissions
        print("Forbidden: \(message)")

    case .notFound(let message):
        // 404 — endpoint or item not found
        print("Not Found: \(message)")

    case .rateLimited(let retryAfter):
        // 429 — too many requests
        print("Rate limited. Retry after: \(retryAfter ?? 0)s")

    case .api(let message, let statusCode, let code, _):
        // Any other API error (500, etc.)
        print("API Error \(statusCode): \(message)")

    case .network(let message):
        // Connection failed, timeout, etc.
        print("Network Error: \(message)")

    case .version(let message):
        // Method requires CoCart Starter
        print("Version Error: \(message)")
    }
}
```

## JWT Token Expiry

Check if a token is expired before making requests, or handle the error after:

```swift
let jwt = client.jwt()

// Proactive check
if jwt.isTokenExpired() {
    try await jwt.refresh()
}

// Or handle the error
do {
    let cart = try await client.cart().get()
} catch let error as CoCartError {
    if case .auth = error, jwt.hasTokens() {
        try await jwt.refresh()
        let cart = try await client.cart().get() // Retry
    } else {
        throw error
    }
}
```

Or let the SDK handle it automatically:

```swift
let result = try await client.jwt().withAutoRefresh {
    try await client.cart().get()
}
```

See [Authentication](authentication.md#auto-refresh) for details.

## HTTP Status Code Mapping

Every HTTP response includes a **status code** — a number that tells you whether the request succeeded or failed, and why. Here's how the SDK maps them to error cases:

| HTTP Status | Error Case | Typical Causes |
|-------------|------------|----------------|
| 400 | `.api` | Invalid request body, missing required fields |
| 401 | `.auth` | Missing or invalid credentials, expired JWT token |
| 403 | `.forbidden` | Insufficient permissions |
| 404 | `.notFound` without an API code, otherwise `.api` | Endpoint not found, item key not found |
| 409 | `.api` | A refused state: an order already paid (`cocart_order_invalid_status`), a payment still in progress, a changed total |
| 429 | `.rateLimited` | Too many requests |
| 500+ | `.api` | Server error |

A `409`, a `429` and a `5xx` are never `.validation`, whatever their code says: `.validation` is only for the SDK's own checks before a request is sent.

## Client-Side Validation Errors

The SDK validates certain inputs before making a network request. These throw `CoCartError.validation` immediately with no HTTP call:

```swift
do {
    try await client.cart().addItem(-1, quantity: 0)
} catch let error as CoCartError {
    if case .validation(let message) = error {
        // message => "Product ID must be a positive integer"
        // No network request was made
    }
}
```

Client-side validation checks:

| Method | Validation | Error Message |
|--------|-----------|---------------|
| `addItem(id, quantity:)` | `id` must be a positive integer | "Product ID must be a positive integer" |
| `addItem(id, quantity:)` | `quantity` must be a positive number | "Quantity must be a positive number" |
| `updateItem(key, quantity:)` | `quantity` must be a positive number | "Quantity must be a positive number" |

Standalone validation functions are also available for use in your own code:

```swift
import CoCart

try validateProductID(123)             // OK
try validateProductID(-1)              // throws CoCartError.validation
try validateQuantity(2)                // OK
try validateQuantity(0)                // throws CoCartError.validation
try validateEmail("user@example.com")  // OK
try validateEmail("not-an-email")      // throws CoCartError.validation
```

## Common Error Scenarios

### Product Not Found

```swift
do {
    try await client.cart().addItem(999999, quantity: 1)
} catch let error as CoCartError {
    if case .api(let message, _, let code, _) = error {
        // message => "Product not found"
        // code    => Optional("cocart_product_not_found")
    }
}
```

### Out of Stock

```swift
do {
    try await client.cart().addItem(123, quantity: 100)
} catch let error as CoCartError {
    if case .api(_, _, let code, _) = error {
        // code => Optional("cocart_not_enough_in_stock")
    }
}
```

### Expired Cart Key

CoCart Starter 5 refuses a cart key with no cart session on every cart route (`404 cocart_invalid_cart`), for example after the cart expired. The client then forgets the stored key (in its storage too) and retries the request once as a new guest, so this error doesn't reach your code for a guest; a fresh cart key comes back as usual.

### Item No Longer in the Cart

Getting, updating or removing an item whose key isn't in the cart (for example, another tab already removed it) fails with `404 cocart_item_not_in_cart`. Since CoCart Starter 5 the error carries the cart as it is now, so you can show it without fetching the cart again:

```swift
do {
    try await client.cart().updateItem(itemKey, quantity: 2)
} catch let error as CoCartError where error.errorCode == "cocart_item_not_in_cart" {
    if let cart = error.getCart() { // nil with CoCart 4.x
        render(cart)
    }
}
```

### Quantity Reduced to the Maximum

Adding more than the purchase limit or the stock allows isn't an error: CoCart adds the maximum and says so with a notice:

```swift
let response = try await client.cart().addItem(123, quantity: 50)
let notices = response.getNotices()["notice"] // ["The quantity of “Beanie” was reduced to 5, the most allowed in the cart."]
```

### Rate Limits

With rate limiting on (CoCart Plus), every response carries `RateLimit-*` headers:

```swift
let rateLimit = response.getRateLimit()
// RateLimitInfo(limit: 25, remaining: 24, reset: 1791108883, retryAfter: nil)
```

`reset` is the Unix time the window resets, and `retryAfter` the seconds to wait after a 429. Exceeding the limit throws `.rateLimited(retryAfter:)`, read from `RateLimit-Retry-After` (what CoCart Plus sends), or from `Retry-After` when that is all a proxy sends.

### Fields at Fault

CoCart Plus checks a whole address or form at once, so one error lists every field at fault:

```swift
do {
    _ = try await client.checkout().update(["billing_address": ["postcode": "nope", "phone": ""]])
} catch let error as CoCartError {
    error.errorCode   // "cocart_invalid_address_fields"
    error.fields      // ["billing.postcode": "Enter a valid postcode.", "billing.phone": "Enter a phone number."]
    error.field       // "billing.postcode"
    error.reason      // e.g. "postcode_format", or nil
}
```

`fields` is empty, and `field` and `reason` are `nil`, for an error that isn't about fields.

### Network / Timeout Errors

A **timeout** occurs when the server takes too long to respond. The SDK cancels the request after the configured number of seconds. After exhausting retries, it throws a network error. This prevents your app from hanging indefinitely if the server is down or overloaded.

```swift
let client = CoCart("https://your-store.com", options: CoCartOptions(
    timeout: 10 // 10 seconds
))

do {
    try await client.cart().get()
} catch let error as CoCartError {
    if case .network(let message) = error {
        print("Network failed: \(message)")
    }
}
```

## Response Data Access

The `CoCartResponse` object supports **dot-notation access** — a way to reach nested values inside the response using a string path with dots. For example, instead of manually traversing dictionaries, you write `response.get("items")`. For deeply nested data, use dots to drill down: `response.get("totals.subtotal")`.

```swift
let response = try await client.cart().get()

// Dot-notation access
response.get("items")
response.get("totals")
response.get("currency")
response.has("items")

// Typed getters
response.getString("totals.total")
response.getInt("item_count")
response.getDouble("totals.fee_total")
response.getBool("needs_payment")

// Cart state helpers
response.getItems()      // [[String: Any]]
response.getTotals()     // [String: Any]
response.getItemCount()  // Int
response.isNotModified() // Bool (304 response)
```
