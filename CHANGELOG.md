# Changelog

All notable changes to DeeplinkKit are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [1.0.0] — Initial Release

### Added

#### Core
- `DeeplinkContext` — immutable value type carrying URL, source, auth state, metadata, and trace ID through the full pipeline
- `DeeplinkSource` — enum covering universalLink, customScheme, pushNotification, shortcutItem, userActivity, widget, programmatic, unknown
- `AuthState` — enum snapshot of authentication at deeplink receipt time
- `DeeplinkQueue` — thread-safe FIFO cold-start buffer with optional UserDefaults persistence
- `NavigationCoordinating` — protocol abstracting navigation from handlers; includes `NoOpNavigationCoordinator` and `RecordingNavigationCoordinator` for tests

#### Models
- `DeeplinkRoute` — typed parsed result with generic `pathParam<T>` / `queryParam<T>` accessors
- `DeeplinkError` — full typed error hierarchy: unresolvable, unsupportedScheme, missingParameter, invalidParameter, noHandlerFound, handlerRejected, blockedByMiddleware, authenticationRequired, navigationFailed, timeout, internal

#### Parser
- `DeeplinkParsing` protocol — stateless URL → DeeplinkRoute transformer
- `StandardURLParser` — handles custom schemes and universal links; supports `:paramName` and `*` path templates
- `CompositeParser` — chain-of-responsibility: tries parsers in order, returns first success

#### Router
- `DeeplinkRouter` — NSLock-backed, priority-ordered handler registry
- Supports static, parameterised, and wildcard path matching
- Supports primary handlers + a registered fallback handler
- `unregister<H>(_:)` for runtime deregistration

#### Handler
- `DeeplinkHandling` protocol — the sole integration surface for feature modules
- Default implementations for `canHandle`, `fallbackURL`, `handlerName`
- `PatternMatcher` — internal utility for pattern-vs-route matching
- `WebFallbackHandler` — opens unmatched links in Safari
- `NoOpHandler` — silently swallows specific patterns (test/debug use)
- `ClosureHandler` — one-off handler backed by a `@Sendable` async closure

#### Middleware
- `DeeplinkMiddleware` protocol — intercept/next chain pattern
- `MiddlewarePipeline` — assembles ordered middleware into a single async chain
- `AuthMiddleware` — blocks unauthenticated access to protected route prefixes
- `AnalyticsMiddleware` — fires `AnalyticsEvent` before and after handling with timing
- `FeatureFlagMiddleware` — gates routes behind async feature flag checks
- `LoggingMiddleware` — structured request/response logging with elapsed time
- `RateLimitMiddleware` — prevents identical deeplinks firing within a configurable interval

#### Manager
- `DeeplinkManager` — single orchestrator; owns parse → middleware → route → handle pipeline
- Cold-start queue with configurable capacity and drain-on-ready
- Configurable handler timeout via `withThrowingTaskGroup`
- `dryRunMode` for test environments
- `onSuccess`, `onError`, `onUnhandled` callbacks
- `DeeplinkRegistrable` protocol for module self-registration

#### Utilities
- `DeeplinkBuilder` — fluent DSL for one-call configuration at app launch
- `DeeplinkLogger` — pluggable logger with `os.Logger` (iOS 14+ / macOS 11+) and print fallback; configurable minimum level
- `DeeplinkDebugger` — `inspect()`, `fire()`, `simulatePush()` for dev/QA builds
- `DeeplinkURLBuilder` — reverse routing: construct URLs from route templates and params
- `RouteRegistry` — centralised named route templates with builder factory
- `DeeplinkTestHelpers` — `DeeplinkTestCase` base class + `XCTAssertPathParam`, `XCTAssertQueryParam`, `XCTAssertDeeplinkError` assertion helpers

#### Extensions
- UIKit/AppDelegate helpers: `handle(openURL:)`, `handle(userActivity:)`, `handle(remoteNotification:)`, `handle(shortcutItem:completionHandler:)`
- SceneDelegate helpers: `handleSceneConnection(options:)`, `handle(urlContexts:)`, `handle(continueUserActivity:)`
- SwiftUI: `.handlesDeeplinks()` view modifier

#### Tests
- `DeeplinkKitTests.swift` — unit tests for context, parser, route, router, middleware pipeline, auth middleware
- `IntegrationTests.swift` — end-to-end pipeline, universal link, cold-start queue, error callbacks, middleware ordering, coordinator recording, queue capacity, built-in handler behaviour, error descriptions

### Platform Support
- iOS 15.0+
- macOS 12.0+
- tvOS 15.0+
- watchOS 8.0+
- Swift 5.9+

---

## [Unreleased]

### Planned
- `DeeplinkSchemeValidator` — validate registered schemes at startup and warn on conflicts
- SwiftUI `@Environment` integration for injecting DeeplinkManager
- Combine publisher bridge for deeplink events
- watchOS complication / widget URL integration helpers
- SPM plugin for deeplink route linting
