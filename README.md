# CoCart Swift SDK

[![Swift](https://img.shields.io/badge/Swift-5.10+-orange?style=for-the-badge&labelColor=000000)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS_17+_|_macOS_14+_|_watchOS_10+-blue?style=for-the-badge&labelColor=000000)](https://developer.apple.com)
[![Zero Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen?style=for-the-badge&labelColor=000000)](https://github.com/cocart-headless/cocart-swift-sdk)
[![Tests](https://img.shields.io/github/actions/workflow/status/cocart-headless/cocart-swift-sdk/tests.yml?label=tests&style=for-the-badge&labelColor=000000)](https://github.com/cocart-headless/cocart-swift-sdk/actions/workflows/tests.yml)
[![License](https://img.shields.io/github/license/cocart-headless/cocart-swift-sdk?color=9cf&style=for-the-badge&labelColor=000000)](https://github.com/cocart-headless/cocart-swift-sdk/blob/main/LICENSE)

Official Swift SDK for the [CoCart](https://cocartapi.com) REST API. Build **headless WooCommerce storefronts** for iOS, macOS, and watchOS — your app talks to WooCommerce through its API instead of rendering PHP templates.

> [!IMPORTANT]
> This SDK is looking for feedback, if you experience a bug please report it.

## TODO to complete the SDK

* [ ] Add SDK docs to documentation site
* [ ] Add support for Cart API extras
* [ ] Add Checkout API support
* [ ] Add Customers Account API support

---

## Requirements

- **Swift 5.10+** — Required for `async/await` and modern concurrency features. Xcode 15.4 or later includes this version.
- **iOS 17+, macOS 14+, or watchOS 10+** — The minimum deployment targets for the SDK.
- **CoCart plugin** installed on your WooCommerce store — This is the WordPress plugin that provides the REST API endpoints the SDK communicates with.
- [CoCart JWT Authentication](https://wordpress.org/plugins/cocart-jwt-authentication/) plugin for JWT features (optional) — Only needed if you want to use JSON Web Token authentication (explained in the [Authentication](docs/authentication.md) guide).

## Support Policy

See [SUPPORT.md](SUPPORT.md) for our versioning policy, supported platforms, and support lifecycle.

## Features

- Zero runtime dependencies — uses native `URLSession` and `Security` framework, no extra packages to install
- Swift Package Manager distribution
- `async/await` with Swift Concurrency throughout
- Client-side input validation (catches errors before network requests)
- Currency formatting utility
- Event system for request/response lifecycle hooks
- Configurable auth header name (for proxies that strip `Authorization`)
- Keychain storage for secure session persistence
- JWT authentication with auto-refresh
- Legacy CoCart plugin support with version-aware field filtering
- ETag conditional requests for reduced bandwidth

## Installation

### Swift Package Manager

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/cocart-headless/cocart-swift-sdk.git", from: "1.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies** and paste the repository URL.

**Zero runtime dependencies** — the SDK does not install any additional packages, keeping your project lightweight.

## Quick Start

An **SDK** (Software Development Kit) is a library that provides ready-made functions for talking to a specific service — in this case, the CoCart REST API on your WooCommerce store. Instead of writing raw HTTP requests yourself, you call simple methods like `client.cart().addItem(123, quantity: 2)` and the SDK handles the details for you.

The `import` statement loads the SDK into your code. The `await` keyword is used before operations that talk to the server, because network requests take time and Swift needs to wait for the response before continuing.

```swift
import CoCart

// Create a client pointing to your WooCommerce store
let client = CoCart("https://your-store.com")

// Browse products (no auth required)
let products = try await client.products().all(["per_page": "12"])

// Add to cart (guest session created automatically)
let response = try await client.cart().addItem(123, quantity: 2)

// Get cart
let cart = try await client.cart().get()
print(cart.getItems())                // Array of items in the cart
print(cart.get("totals.total"))       // Reach into nested data with dot notation
```

> **Note:** Code using `await` must be inside an `async` function or task. In SwiftUI, use `.task { }` modifiers. In a plain script or app delegate, wrap your code in a `Task`:
>
> ```swift
> Task {
>     let client = CoCart("https://your-store.com")
>     let cart = try await client.cart().get()
>     print(cart.getItems())
> }
> ```

## Documentation

| Guide | Description |
|-------|-------------|
| [Configuration & Setup](docs/installation.md) | Options, fluent config, white-labelling, legacy mode |
| [Authentication](docs/authentication.md) | Guest, Basic Auth, JWT, consumer keys |
| [Cart API](docs/cart.md) | Add, update, remove items, coupons, shipping, fees |
| [Products API](docs/products.md) | List, filter, search, categories, tags, attributes |
| [Sessions API](docs/sessions.md) | Admin sessions, storage adapters, guest session lifecycle |
| [Error Handling](docs/error-handling.md) | Error types, catching errors, common scenarios |
| [Utilities](docs/utilities.md) | Currency formatter, event system, secure session storage |

## CoCart Channels

We have different channels at your disposal where you can find information about the CoCart project, discuss it and get involved:

[![Twitter: cocartapi](https://img.shields.io/twitter/follow/cocartapi?style=social)](https://twitter.com/cocartapi) [![CoCart GitHub Stars](https://img.shields.io/github/stars/cocart-headless/cocart-swift-sdk?style=social)](https://github.com/cocart-headless/cocart-swift-sdk)

<ul>
  <li>📖 <strong>Documentation</strong>: this is the place to learn how to use CoCart API. <a href="https://cocartapi.com/docs/?utm_medium=gh&utm_source=github&utm_campaign=readme&utm_content=cocart">Get started!</a></li>
  <li>👪 <strong>Community</strong>: use our Discord chat room to share any doubts, feedback and meet great people. This is your place too to share <a href="https://cocartapi.com/community/?utm_medium=gh&utm_source=github&utm_campaign=readme&utm_content=cocart">how are you planning to use CoCart!</a></li>
  <li>🐞 <strong>GitHub</strong>: we use GitHub for bugs and pull requests, doubts are solved with the community.</li>
  <li>🐦 <strong>Social media</strong>: a more informal place to interact with CoCart users, reach out to us on <a href="https://twitter.com/cocartapi">X/Twitter.</a></li>
</ul>

## Credits

Website [cocartapi.com](https://cocartapi.com/?ref=github) &nbsp;&middot;&nbsp;
GitHub [@cocart-headless](https://github.com/cocart-headless) &nbsp;&middot;&nbsp;
X/Twitter [@cocartapi](https://twitter.com/cocartapi) &nbsp;&middot;&nbsp;
[Facebook](https://www.facebook.com/cocartforwc/) &nbsp;&middot;&nbsp;
[Instagram](https://www.instagram.com/cocartheadless/)

## License

MIT
