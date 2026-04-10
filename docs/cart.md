# Cart API

The Cart API handles all shopping cart operations — adding items, updating quantities, applying coupons, managing shipping, and more. This is the core of any headless WooCommerce storefront.

**How cart sessions work:**

- **Guest customers** — The first request creates a new guest session. The server returns a `Cart-Key` (a unique identifier like `guest_abc123`) which the SDK extracts and stores automatically in the Keychain. All subsequent requests use this key so the server knows which cart belongs to which visitor.
- **Authenticated customers** — The server identifies the cart by the WordPress user account. No cart key is needed because the server already knows who you are from your authentication credentials.

To access cart methods, call `client.cart()`:

```swift
let cart = client.cart()
```

## Create Cart

Create a new guest cart session without adding items. Only available for non-authenticated (guest) users.

```swift
let response = try await client.cart().create()
print(response.getString("cart_key")) // Optional("guest_abc123...")
```

## Get Cart

```swift
let response = try await client.cart().get()

// With parameters
let response = try await client.cart().get(["thumb": "true", "default": "true"])
```

### Type-Safe Field Filtering

A full cart response includes many fields (items, totals, coupons, shipping, customer, etc.). If you only need a few of them, `getFiltered()` tells the server to send back only the fields you list. This means less data transferred and faster responses, especially on slow connections.

```swift
let response = try await client.cart().getFiltered(["items", "totals"])
```

This sends `?_fields=items,totals` to the server, so only those fields are returned over the wire.

## Client-Side Validation

**Client-side validation** means the SDK checks your inputs _before_ sending anything to the server. If you pass an invalid product ID (like `-1`) or a quantity of `0`, the SDK throws an error immediately. This saves time because you don't have to wait for a server round-trip just to find out the input was bad.

```swift
do {
    try await client.cart().addItem(-1, quantity: 0)
} catch let error as CoCartError {
    // error == .validation("Product ID must be a positive integer")
    // No network request was made
}
```

Validation rules:

- **Product ID** — Must be a positive integer (`addItem`, `addVariation`)
- **Quantity** — Must be a positive number (`addItem`, `addVariation`, `updateItem`)

You can also use the validation functions directly:

```swift
import CoCart

try validateProductID(123)             // OK
try validateProductID(-1)              // throws CoCartError.validation
try validateQuantity(2)                // OK
try validateQuantity(0)                // throws CoCartError.validation
try validateEmail("user@example.com")  // OK
try validateEmail("not-an-email")      // throws CoCartError.validation
```

## Adding Items

### Add a Simple Product

```swift
// Product ID 123, quantity 2
let response = try await client.cart().addItem(123, quantity: 2)

// Shorthand
let response = try await client.cart().add(123, quantity: 2)
```

### Add with Options

```swift
let response = try await client.cart().addItem(123, quantity: 1, options: [
    "item_data": [
        "gift_message": "Happy Birthday!",
        "engraving": "John"
    ],
    "email": "customer@email.com",
    "return_item": true
])
```

### Add a Variable Product

A **variable product** is a product with options like size or color. In WooCommerce, these are called "variations." When adding a variable product, you specify which variation the customer chose:

```swift
let response = try await client.cart().addVariation(456, quantity: 1, attributes: [
    "attribute_pa_color": "blue",
    "attribute_pa_size": "large"
])
```

### Add Multiple Items at Once

```swift
let response = try await client.cart().addItems([
    ["id": "123", "quantity": "2"],
    ["id": "456", "quantity": "1"],
    ["id": "789", "quantity": "3"]
])
```

## Updating Items

Every item in the cart has a unique **item key** — a long string like `abc123def456...` that identifies that specific item. You receive item keys in cart responses (in the `item_key` field of each item). You use this key to tell the server which item you want to update or remove.

```swift
// Item keys are returned in cart responses
let response = try await client.cart().updateItem("abc123def456...", quantity: 5)

// With additional options
let response = try await client.cart().updateItem("abc123def456...", quantity: 3, options: [
    "item_data": ["gift_wrap": true]
])
```

### Update Multiple Items at Once

```swift
let response = try await client.cart().updateItems([
    "abc123def456...": 3,
    "def789ghi012...": 1
])
```

## Removing & Restoring Items

### Remove an Item

```swift
let response = try await client.cart().removeItem("abc123def456...")
```

### Remove Multiple Items at Once

```swift
let response = try await client.cart().removeItems([
    "abc123def456...",
    "def789ghi012..."
])
```

### Restore a Removed Item

```swift
let response = try await client.cart().restoreItem("abc123def456...")
```

### Get Removed Items

```swift
let response = try await client.cart().getRemovedItems()
```

## Cart Management

### Clear Cart

```swift
let response = try await client.cart().clear()

// Alias
let response = try await client.cart().empty()
```

### Calculate Totals

```swift
let response = try await client.cart().calculate()
```

### Update Cart

```swift
let response = try await client.cart().update([
    "customer_note": "Please gift wrap."
])
```

## Totals & Counts

### Get Totals

```swift
// Raw values
let response = try await client.cart().getTotals()

// Formatted with currency (HTML)
let response = try await client.cart().getTotals(formatted: true)
```

### Get Item Count

```swift
let response = try await client.cart().getItemCount()
```

### Get Cart Items

Get only the items in the cart (lighter than fetching the full cart):

```swift
let response = try await client.cart().getItems()
```

### Get a Single Cart Item

```swift
let response = try await client.cart().getItem("abc123def456...")
```

## Coupons

> Requires the CoCart Plus plugin.

### Apply a Coupon

```swift
let response = try await client.cart().applyCoupon("SUMMER20")
```

### Remove a Coupon

```swift
let response = try await client.cart().removeCoupon("SUMMER20")
```

### Get Applied Coupons

```swift
let response = try await client.cart().getCoupons()
```

### Validate Applied Coupons

```swift
let response = try await client.cart().checkCoupons()
```

## Customer Details

### Update Customer

```swift
// Update billing address
let response = try await client.cart().updateCustomer(billing: [
    "first_name": "John",
    "last_name": "Doe",
    "email": "john@example.com",
    "phone": "+1234567890",
    "address_1": "123 Main St",
    "city": "New York",
    "state": "NY",
    "postcode": "10001",
    "country": "US"
])

// Update both billing and shipping
let response = try await client.cart().updateCustomer(
    billing: ["email": "john@example.com"],
    shipping: ["address_1": "456 Oak Ave", "city": "Los Angeles", "state": "CA"]
)
```

### Get Customer Details

```swift
let response = try await client.cart().getCustomer()
```

## Shipping

### Get Available Shipping Methods

```swift
let response = try await client.cart().getShippingMethods()
```

### Set Shipping Method

> Requires the CoCart Plus plugin.

```swift
let response = try await client.cart().setShippingMethod("flat_rate:1")
```

### Calculate Shipping

```swift
let response = try await client.cart().calculateShipping([
    "country": "US",
    "state": "CA",
    "postcode": "90001",
    "city": "Los Angeles"
])
```

## Fees

> Requires the CoCart Plus plugin.

### Get Cart Fees

```swift
let response = try await client.cart().getFees()
```

### Add a Fee

```swift
// Non-taxable fee
let response = try await client.cart().addFee("Rush Processing", amount: 9.99)

// Taxable fee
let response = try await client.cart().addFee("Gift Wrapping", amount: 4.99, taxable: true)
```

### Remove All Fees

```swift
let response = try await client.cart().removeFees()
```

## Cross-Sells

**Cross-sells** are product recommendations based on what's currently in the cart. For example, if a customer has a laptop in their cart, cross-sells might suggest a laptop bag or mouse. These are configured in WooCommerce's product settings.

```swift
let response = try await client.cart().getCrossSells()
```

## ETag / Conditional Requests

**ETag** (Entity Tag) is a caching mechanism. When the server responds, it includes an `ETag` header — a unique fingerprint of the data. On the next request, the SDK automatically sends this fingerprint back via `If-None-Match`. If the data hasn't changed, the server responds with `304 Not Modified` (no body), saving bandwidth and speeding up responses.

ETag support is **enabled by default**.

```swift
// First request: full response with ETag header
let response = try await client.cart().get()

// Second request: sends If-None-Match automatically
let response2 = try await client.cart().get()
if response2.isNotModified() {
    print("Cart has not changed")
}
```

### Disable ETag

```swift
// Via constructor
let client = CoCart("https://your-store.com", options: CoCartOptions(etag: false))

// At runtime
client.setETag(false)
```

### Cache Status

The `CoCart-Cache` response header indicates server-side cache status:

```swift
let response = try await client.cart().get()
print(response.getCacheStatus()) // Optional("HIT"), Optional("MISS"), or Optional("SKIP")
```

## Working with Responses

Every cart method returns a `CoCartResponse` that wraps the server's reply. Instead of digging through raw JSON, you can use helper methods to access common data. The `get()` method supports **dot notation** — a way to reach nested values using dots (e.g., `"totals.subtotal"` instead of manually traversing dictionaries):

```swift
let response = try await client.cart().get()

// Cart items
let items = response.getItems()

// Cart totals
let totals = response.getTotals()

// Item count
let count = response.getItemCount()

// Cart key (from headers)
let cartKey = response.getCartKey()

// Cart hash
let hash = response.getCartHash()

// Notices
let notices = response.getNotices()

// Dot-notation access
let subtotal = response.getString("totals.subtotal")
let firstItemName = response.getString("items.0.name")

// Check if key exists
if response.has("totals.discount_total") {
    print("Discount applied!")
}

// Full data
let data = response.toDictionary()
let json = try response.toJSON()

// Decode into your own Codable models
let decoded = try response.decode(MyCartModel.self)
```

See [Error Handling](error-handling.md) for handling API errors.
