# Configuration & Setup

For installation instructions and requirements, see the [README](../README.md#installation).

## Configuration Options

The second argument to `CoCart()` is an optional `CoCartOptions` struct where you can set various options. You only need to include the ones relevant to your setup — everything has sensible defaults.

```swift
let client = CoCart("https://your-store.com", options: CoCartOptions(
    // Guest session
    cartKey: "existing_cart_key",

    // Basic Auth
    username: "customer@email.com",
    password: "password",

    // JWT Auth
    jwtToken: "your-jwt-token",
    jwtRefreshToken: "your-refresh-token",

    // Admin (Sessions API)
    consumerKey: "ck_xxxxx",
    consumerSecret: "cs_xxxxx",

    // HTTP settings
    timeout: 30,           // seconds (default: 30)

    // REST API prefix (default: "wp-json")
    restPrefix: "wp-json",

    // API namespace (default: "cocart")
    namespace: "cocart",

    // CoCart main plugin: .basic (default) or .legacy
    mainPlugin: .basic,

    // Retry transient failures (default: 2)
    maxRetries: 2,

    // Storage adapter — KeychainStorage by default, MemoryStorage for tests/previews
    storage: MemoryStorage(),
    storageKey: "cocart_cart_key",

    // Custom auth header name (default: "Authorization")
    // Useful when hosting strips the Authorization header
    authHeaderName: "X-Auth-Token",

    // Enable ETag conditional requests for reduced bandwidth (default: true)
    etag: true,

    // Enable debug logging (default: false)
    debug: true
))
```

### Fluent Configuration

A **fluent API** (also called method chaining) lets you call multiple configuration methods in a single expression. Each method returns the client itself, so you can chain them with dots instead of writing separate statements:

```swift
let client = CoCart.create("https://your-store.com")
    .setTimeout(60)
    .setMaxRetries(2)
    .setRestPrefix("api")
    .setNamespace("mystore")
    .addHeader("X-Custom-Header", value: "value")
    .setAuthHeaderName("X-Auth-Token")
    .setETag(true)
    .setMainPlugin(.basic)
    .setDebug(true)
```

This is equivalent to writing each call on its own line:

```swift
let client = CoCart("https://your-store.com")
client.setTimeout(60)
client.setMaxRetries(2)
// ... and so on
```

## White-Labelling / Custom REST Prefix

WordPress exposes its REST API at `/wp-json/` by default. The SDK builds URLs like `https://your-store.com/wp-json/cocart/v2/cart`. If your site or hosting changes this prefix, or if the CoCart plugin has been renamed (white-labelled), you can configure the SDK to match:

```swift
// Custom REST prefix (site uses /api/ instead of /wp-json/)
let client = CoCart("https://your-store.com", options: CoCartOptions(
    restPrefix: "api"
))
// Requests go to: https://your-store.com/api/cocart/v2/cart

// White-labelled namespace
let client2 = CoCart("https://your-store.com", options: CoCartOptions(
    namespace: "mystore"
))
// Requests go to: https://your-store.com/wp-json/mystore/v2/cart

// Both together
let client3 = CoCart("https://your-store.com", options: CoCartOptions(
    restPrefix: "api",
    namespace: "mystore"
))
// Requests go to: https://your-store.com/api/mystore/v2/cart
```

## Legacy Plugin Support

The SDK supports both **CoCart Basic** and the **legacy CoCart plugin** (`cart-rest-api-for-woocommerce` v4.x). By default, the SDK targets CoCart Basic.

To use the SDK with the legacy plugin, set `mainPlugin` to `.legacy`:

```swift
let client = CoCart("https://your-store.com", options: CoCartOptions(
    mainPlugin: .legacy
))

// Or use the fluent setter
client.setMainPlugin(.legacy)
```

### What changes in legacy mode

**Field filtering uses `fields` instead of `_fields`.** The legacy plugin uses CoCart's custom `fields` query parameter, while CoCart Basic uses the WordPress standard `_fields`. The SDK handles this automatically — methods like `getFiltered()` will send the correct parameter based on the configured main plugin.
