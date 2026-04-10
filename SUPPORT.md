<!-- CoCart SDK Support Policy Template v1 -->

# Support & Versioning Policy

> **Note:** This SDK is currently in development. The full support lifecycle (maintenance phase for previous major versions, EOL grace periods) takes effect once the SDK is declared stable and production-ready.

## Versioning

This SDK follows [Semantic Versioning](https://semver.org/) (SemVer):

- **Major** (X.0.0) — Breaking changes to the public API
- **Minor** (x.Y.0) — New features that are backward-compatible
- **Patch** (x.y.Z) — Bug fixes and security patches

Only the **latest major version** receives active development. Older major versions remain available for install but receive no updates. Migration guides are provided in the `docs/` folder for major version upgrades.

### What constitutes a breaking change

- Removing or renaming a public class, struct, enum, function, or protocol
- Changing required parameters of a public method
- Changing return types in a way that breaks type assignability
- Dropping a platform from the supported matrix
- Raising the minimum Swift version or platform deployment target

### What is NOT a breaking change

- Adding new optional parameters to existing methods (with default values)
- Adding new public types, methods, or properties
- Internal refactors that do not affect the public API
- Adding a new platform to the supported matrix
- Bug fixes that correct behavior to match documentation

## SDK Lifecycle

| Phase | Description | Duration |
|---|---|---|
| **Active** | New features, bug fixes, security patches | Current major version |
| **Maintenance** | Security patches and critical bug fixes only | Previous major version, 12 months |
| **Deprecated** | No updates; remains installable | After maintenance ends |

## Supported Platforms

| Platform | Minimum Version | Status |
|---|---|---|
| iOS | 17.0 | Supported, tested in CI |
| macOS | 14.0 | Supported, tested in CI |
| watchOS | 10.0 | Supported, build-tested in CI |

### Swift compatibility

| Swift | Support |
|---|---|
| 5.10+ | Required; tested in CI |
| 6.0+ | Supported |

### Xcode compatibility

| Xcode | Support |
|---|---|
| 16.0+ | Recommended; tested in CI |
| 15.4+ | Minimum supported version |

### Version support policy

We support all Apple platform versions that are within the **current and previous major OS release** cycle. The SDK requires Swift 5.10+ for `async/await` and modern concurrency features.

- **Adding new platforms:** When a new OS version ships (typically each September), we add CI testing and official support.
- **Dropping old versions:** When a platform version is two major releases behind, we drop it in the next major SDK release.

## Deprecation Notices

We communicate deprecations through:

1. **DocC annotations** — `@available(*, deprecated)` annotations that render as warnings in Xcode
2. **Changelog entry** — Every deprecation is noted in release notes
3. **Minimum one minor release** — A deprecation notice ships at least one minor version before the deprecated feature is removed
4. **Migration guide** — Major version upgrades include a migration guide in the `docs/` folder

## Getting Help

- **Documentation:** https://cocartapi.com/docs
- **Community:** https://cocartapi.com/community
- **Issues:** https://github.com/cocart-headless/cocart-swift-sdk/issues
