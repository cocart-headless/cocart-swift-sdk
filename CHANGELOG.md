# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

### Added

- `CoCart` main client with fluent configuration API
- Guest session management with automatic cart key capture and Keychain persistence
- Basic Auth, JWT (login/refresh/logout/auto-refresh), and Consumer Key authentication
- `CartResource` with full cart operations: add, update, remove, restore, clear, calculate
- CoCart Plus support: coupons, customer addresses, shipping methods, fees, cross-sells
- `ProductsResource` for browsing products, variations, categories, tags, attributes, reviews
- `SessionsResource` for admin session management
- `JWTResource` with token refresh, validation, expiry checking, and auto-refresh wrapper
- `CoCartResponse` with dot-notation access, typed getters, and `Codable` decoding
- `CurrencyFormatter` for formatting raw integer amounts with store currency settings
- `KeychainStorage` (default) and `MemoryStorage` (tests/previews) implementations
- ETag caching for conditional GET requests
- Automatic retry with exponential backoff on transient network errors
- Event system for monitoring requests, responses, and errors
- Input validation for product IDs, quantities, and email addresses
- Structured error types via `CoCartError` enum
