# Account API

> **Note:** The Account API is fully supported by this SDK, but the Account
> API itself is not yet available in a released version of the CoCart
> plugin — it's coming in a future release. This documentation is ready for
> when it ships.

The Account resource gives an authenticated customer access to their own profile, password, address, order history, downloads, reviews and subscriptions, plus methods that don't need a login: registering a new customer and requesting an order withdrawal.

All other methods require the customer to be authenticated (Basic Auth or JWT).

```swift
let client = CoCart("https://your-store.com")
    .setJWTToken("eyJ...")
```

The customer, an order and a subscription come back as documents (CoCart Plus 2.0): each has `object` (`customer`, `order`, `subscription`), and the record's fields; an order or subscription also has `allowed_actions` (the names of what the customer may do with it now, e.g. `pay` or `cancel`). A request that changes something also sends `result`, with `code` and a `message` for the customer: `account_updated`, `account_created`, and so on.

The methods that read a document take `formatted: true` (amounts formatted for display, `"$18.00"`, instead of minor units, `"1800"`) and `metaKeys` (only these keys in its `meta`): `getProfile()`, `getOrder(_:)`, `getGuestOrder(_:email:)` and `getSubscription(_:)`. The list methods (`getOrders(_:)`, `getSubscriptions(_:)`) take them in their parameters as `formatted` and `meta_keys`.

### Register

Registers a new customer account. Unlike the other account methods, `register()` doesn't need the customer to be logged in: it's the entry point before authentication.

```swift
let client = CoCart("https://your-store.com")

let response = try await client.account().register(
    email: "jane@example.com",
    username: "jane",              // optional if the store generates usernames from email
    password: "a-strong-password"  // optional if the store generates passwords
)

response.statusCode               // 201
response.getString("object")      // "customer"
response.getString("result.code") // "account_created"
```

It answers `201` with the new customer. It doesn't log the customer in: log in next.

The username and password are sent as `requested_username` and `requested_password`, not `username` and `password`: CoCart treats a request with non-empty `username`/`password` fields as a Basic Auth attempt, which would reject the registration.

| Status | Code | Meaning |
|--------|------|---------|
| `400` | `cocart_invalid_email` | Email missing or invalid |
| `400` | `cocart_registration_invalid_username`, `cocart_registration_reserved_username` | The requested username can't be used (e.g. `admin`) |
| `400` | `cocart_registration_missing_password`, `cocart_registration_weak_password` | The store needs a (stronger) password |
| `400` | `cocart_account_creation_failed` | WooCommerce couldn't create the account |
| `409` | `cocart_account_exists` | Email is already registered |
| `409` | `cocart_registration_username_exists` | Username is already taken |

### Get Profile

```swift
let response = try await client.account().getProfile()
print(response.getString("email") ?? "")
print(response.get("billing") ?? [:])
```

### Update Profile

Send only what changes. It returns the customer with `account_updated` in `result`; every field at fault is reported at once (`CoCartError.fields`).

```swift
let response = try await client.account().updateProfile([
    "account_first_name": "Jane",
    "account_last_name": "Doe",
    "account_display_name": "Jane Doe",
    "account_email": "jane@example.com",
])
```

### Change Password

```swift
let response = try await client.account().changePassword(
    current: "old-password",
    password: "new-password",
    confirm: "new-password"
)
response.getString("result.code") // "account_updated"
```

It sends only `password_current`, `password_1` and `password_2` to `POST my-account`, in one request. A wrong current password is `400 cocart_account_incorrect_current_password`.

### Update Address

Saves the customer's billing and/or shipping address. Fields are unprefixed:

```swift
let address = ["first_name": "Jane", "address_1": "1 Main St", "city": "Paris", "postcode": "75001", "country": "FR"]
let response = try await client.account().updateAddress([
    "billing_address": address,
    "shipping_address": address,
])
```

### Get Order History

The customer's orders, newest first, with `pagination` (also in the `X-WP-Total` and `X-WP-TotalPages` headers):

```swift
let response = try await client.account().getOrders()
let orders = response.get("orders") as? [[String: Any]] ?? []

// Paged and filtered
let filtered = try await client.account().getOrders([
    "page": 2,
    "per_page": 10,
    "order": "DESC",
    "status": ["processing", "on-hold"],   // one status, or a list
    "after": "2026-01-01T00:00:00",        // ISO 8601
    "before": "2026-12-31T23:59:59",
    "subscription_order_type": "renewal",  // parent, renewal, switch or resubscribe
    "formatted": true,
    "meta_keys": ["gift_message"],
])
```

A list is sent comma-joined, and a `Bool` as `"true"` or `"false"`.

### Get a Single Order

```swift
let response = try await client.account().getOrder(123)
response.getString("status.code") // "processing"

// Amounts formatted for display, and only some meta
let formatted = try await client.account().getOrder(123, formatted: true, metaKeys: ["gift_message"])
```

Someone else's order is `404 cocart_order_not_found`.

### Get a Guest Order

Looks up an order placed as a guest, verified by billing email. It comes without its `key`. Lookups are rate limited (`429 cocart_guest_lookup_rate_limited`).

```swift
let response = try await client.account().getGuestOrder(123, email: "jane@example.com")
```

### Cancel an Order

Cancels one of the customer's orders where WooCommerce allows it (for example a pending or failed order). Otherwise it's `409 cocart_order_cannot_be_cancelled`.

```swift
let response = try await client.account().cancelOrder(123)
response.getString("status.code") // "cancelled"
```

### Get Downloads for an Order

`GET my-account/orders/{id}/downloads`. It returns the list of downloads, like `getDownloads()`: read it with `toArray()`.

```swift
let response = try await client.account().getOrderDownloads(123)

// For a guest order, looked up with its billing email
let guest = try await client.account().getGuestOrderDownloads(123, email: "jane@example.com")

for case let download as [String: Any] in response.toArray() {
    print(download)
}
```

### Get All Downloads

```swift
let response = try await client.account().getDownloads() // the list of downloads: response.toArray()
```

### Get Reviews

Returns the reviews the customer has submitted (`GET products/reviews/mine`, the same as `products().myReviews()`):

```swift
let response = try await client.account().getReviews()
```

### Email Verification

```swift
// Confirm a pending email change, with the key and user ID from the emailed link.
_ = try await client.account().verifyEmail(key: key, userID: userID)

// Prove ownership of the account email so WooCommerce links past guest orders to it (WooCommerce 11+).
let status = try await client.account().sendOrderEmailVerification().getString("status") // "sent" or "throttled" (once a minute)
_ = try await client.account().verifyOrderEmail(key: key, userID: userID)
```

### Subscriptions

Needs WooCommerce Subscriptions.

```swift
let list = try await client.account().getSubscriptions(["page": 1, "per_page": 10, "status": ["active", "on-hold"]])
let one = try await client.account().getSubscription(512)
let asGuest = try await client.account().getSubscription(512, email: "jane@example.com")

_ = try await client.account().suspendSubscription(512)
_ = try await client.account().reactivateSubscription(512)
_ = try await client.account().cancelSubscription(512)
_ = try await client.account().setSubscriptionAutoRenew(512, enabled: false)

// Resubscribe puts the ended subscription's items in the cart; check out as usual, or undo it.
_ = try await client.account().resubscribe(512)
_ = try await client.account().cancelResubscribe(512)
```

### Changing a Subscription's Payment Method

> Requires WooCommerce Subscriptions. The customer must be logged in.

A subscription can switch to a card the customer has saved, or to a new one. Use a gateway that can charge renewals (`supports.subscriptions` in `getPaymentMethods()`, or `supportsSubscriptions` on a saved method).

`updateSubscriptionPaymentMethod(_:_:)` can take payment like checkout, so it returns the same [`CheckoutResult`](checkout.md#reading-the-result), read from the subscription the store sends back: `object` is `subscription`, with `subscriptionId`. A new card may need 3D Secure.

**With a saved card:**

```swift
let saved = try await client.checkout().getSavedPaymentMethods().filter(\.supportsSubscriptions)
let card = saved[0] // the one the customer picked: card.label is e.g. "Visa ending in 4242"

let result = try await client.account().updateSubscriptionPaymentMethod(512, [
    "payment_method": card.gatewayId,
    "token_id": card.id,
])
```

**With a new card**, create a payment method as in the [Quick Start](checkout.md#quick-start):

```swift
let result = try await client.account().updateSubscriptionPaymentMethod(512, [
    "payment_method": "stripe",
    "payment_data": ["wc-stripe-payment-method": paymentMethod.stripeId],
])
```

The new card is saved to the customer's account, since the renewals charge it.

**Reading the result:**

```swift
if result.isComplete {                           // result.code == .paymentMethodChanged
    result.subscriptionId                        // 512
    result.message                               // "Your subscription will now be paid with Visa ending in 4242."
    result.response.getString("payment.title")   // "Visa ending in 4242"
} else if result.needsConfirmation {
    try await confirmCard(result) // then call updateSubscriptionPaymentMethod(_:_:) again with the same input
} else if result.needsRedirect {
    try await openOffSite(result.redirectUrl!)
} else {
    showError(result.message)
}
```

Confirm as in [3D Secure in the App](checkout.md#3d-secure-in-the-app); a new card usually gives a SetupIntent (`result.intentType` is `"setup_intent"`). After an off-site step, `checkout().confirmReturn(_:)` finishes the change.

| Code | HTTP | Meaning |
|---|---|---|
| `cocart_subscription_not_found` | 404 | No such subscription for this customer |
| `cocart_invalid_payment_method` | 400 | The payment method or saved card can't be used: it isn't the customer's, or no longer exists |
| `cocart_subscription_payment_method_change_unsupported` | 400 | The subscription's payment method can't be changed |
| `cocart_subscription_payment_token_required` | 400 | Pass a saved card's `token_id`, or a new card in `payment_data` |
| `cocart_subscription_payment_token_needs_confirmation` | 400 | The saved card must be confirmed before it can pay renewals |
| `cocart_subscription_cannot_change_payment_method` | 409 | The subscription's state doesn't allow a change now |
| `cocart_payment_in_progress` | 409 | Another change is still running for it |

A declined card isn't an error: it comes back as a failed result, as at checkout.

### Order Withdrawal

Submits a right-of-withdrawal request (WooCommerce's order withdrawal feature). No login needed; the response is the same whether or not the order matched:

```swift
_ = try await client.account().requestOrderWithdrawal([
    "first_name": "Jane",
    "last_name": "Doe",
    "email": "jane@example.com",
    "email_confirmation": "jane@example.com",
    "order_number": "1042",
    "withdrawal_type": "full_order", // or "specific_items_only" with additional_details
])
```

See [Error Handling](error-handling.md) for how a missing CoCart plugin/version is reported (a `cocart_plugin_required` error) when calling these methods.
