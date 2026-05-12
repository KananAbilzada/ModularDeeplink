# DeeplinkKit

A fully decoupled, protocol-driven deeplink system for Swift. Handles custom schemes, universal links, push notifications, widgets, and shortcuts — through a single, scalable pipeline.

---

## Features

- ✅ **Protocol-first** — every layer is swappable
- ✅ **Async/await** throughout
- ✅ **Middleware chain** — auth, analytics, feature flags, rate limiting, logging
- ✅ **Module registration** — each micro-app plugs in with one method
- ✅ **Cold-start queue** — links received before navigation is ready are buffered
- ✅ **Priority-based routing** — multiple handlers can compete; highest wins
- ✅ **Fluent builder DSL** — clean, readable setup at launch
- ✅ **SwiftUI + UIKit** support
- ✅ **Comprehensive tests**

---

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0           |
| macOS    | 12.0           |
| tvOS     | 15.0           |
| watchOS  | 8.0            |
| Swift    | 5.9            |

---

## Installation

### Swift Package Manager

In `Package.swift`:

```swift
.package(url: "https://github.com/KananAbilzada/ModularDeeplink", from: "1.0.0")
```

Or add it via Xcode: **File → Add Package Dependencies**.

---

## Quick Start

### 1. Configure at app launch

```swift
// AppDelegate.swift or App.swift
import DeeplinkKit

@main
struct MyApp: App {
    init() {
        DeeplinkBuilder()
            .schemes(["myapp"])
            .universalLinkHosts(["app.example.com"])
            .routes([
                "product/:productId",
                "profile/:userId",
                "store/:storeId/product/:productId",
                "home",
                "settings/:section"
            ])
            .middleware(LoggingMiddleware())
            .middleware(AuthMiddleware(protectedRoutes: ["profile", "orders"]))
            .middleware(AnalyticsMiddleware { event in
                Analytics.track("deeplink_received", properties: ["route": event.routeIdentifier ?? ""])
            })
            .modules([StoreModule(), ProfileModule(), ChatModule()])
            .fallback(WebFallbackHandler(baseWebURL: URL(string: "https://app.example.com")))
            .onError { context, error in
                CrashReporter.record(error)
            }
            .build()

        DeeplinkManager.shared.markReady()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .handlesDeeplinks() // SwiftUI extension
        }
    }
}
```

### 2. Implement a handler in your module

```swift
// StoreModule/ProductDeeplinkHandler.swift
import DeeplinkKit

final class ProductDeeplinkHandler: DeeplinkHandling {
    let priority = 100
    let supportedPatterns = ["product/:productId", "store/:storeId/product/:productId"]
    let fallbackURL = URL(string: "https://app.example.com/store")

    func handle(context: DeeplinkContext) async throws {
        guard let productId = context.resolvedRoute?.pathParams["productId"] else {
            throw DeeplinkError.missingParameter("productId")
        }
        let storeId = context.resolvedRoute?.pathParams["storeId"]  // optional

        await MainActor.run {
            NavigationCoordinator.shared.openProduct(id: productId, storeId: storeId)
        }
    }
}
```

### 3. Register in your module

```swift
// StoreModule/StoreModule.swift
import DeeplinkKit

extension StoreModule: DeeplinkRegistrable {
    public func registerDeeplinks(in manager: DeeplinkManager) {
        manager.register(handler: ProductDeeplinkHandler())
        manager.register(handler: CategoryDeeplinkHandler())
        manager.register(handler: CheckoutDeeplinkHandler())
    }
}
```

---

## Architecture

```
URL Entry (AppDelegate / SceneDelegate / SwiftUI)
         │
         ▼
DeeplinkManager.process(url:source:)
         │
         ▼
DeeplinkContext  ──  captures URL, source, auth state, metadata
         │
         ▼
DeeplinkParser  ──  URL → DeeplinkRoute (identifier + params)
         │
         ▼
MiddlewarePipeline  ──  auth gate · analytics · feature flags · logging
         │
         ▼
DeeplinkRouter  ──  priority-ordered registry → best handler
         │
         ▼
DeeplinkHandler.handle(context:)  ──  your navigation code
         │
         ▼
onSuccess / onError callbacks
```

---

## Core Types

### `DeeplinkContext`
Immutable value type flowing through the entire pipeline.

```swift
public struct DeeplinkContext {
    let url: URL
    let source: DeeplinkSource      // .customScheme, .universalLink, .pushNotification, etc.
    let authState: AuthState        // .authenticated(userID:), .unauthenticated, .unknown
    let metadata: [String: String]  // arbitrary extras (e.g. push payload)
    let traceID: String             // UUID for logging
    var resolvedRoute: DeeplinkRoute? // set after parsing
}
```

### `DeeplinkRoute`
Typed result of parsing.

```swift
public struct DeeplinkRoute {
    let identifier: String           // "product" for myapp://product/123
    let pathParams: [String: String] // ["productId": "123"]
    let queryParams: [String: String]
    let fragment: String?
}

// Type-safe accessors:
let id: Int? = route.pathParam("productId", as: Int.self)
let page: Int? = route.queryParam("page", as: Int.self)
```

### `DeeplinkHandling` Protocol
The only interface your feature modules implement.

```swift
public protocol DeeplinkHandling: AnyObject, Sendable {
    var priority: Int { get }
    var supportedPatterns: [String] { get }
    func handle(context: DeeplinkContext) async throws

    // Default implementations provided:
    var fallbackURL: URL? { get }
    var handlerName: String { get }
    func canHandle(route: DeeplinkRoute) -> Bool
}
```

### `DeeplinkMiddleware` Protocol

```swift
public protocol DeeplinkMiddleware: Sendable {
    var middlewareName: String { get }
    func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws
}
```

---

## Built-in Middleware

| Middleware | Purpose |
|---|---|
| `LoggingMiddleware` | Structured logs with timing for every link |
| `AuthMiddleware` | Block protected routes for unauthenticated users |
| `AnalyticsMiddleware` | Fire analytics events before + after handling |
| `FeatureFlagMiddleware` | Gate routes behind feature flags |
| `RateLimitMiddleware` | Throttle duplicate deeplinks |

---

## Built-in Handlers

| Handler | Purpose |
|---|---|
| `WebFallbackHandler` | Open unmatched routes in Safari |
| `NoOpHandler` | Silently swallow specific routes |
| `ClosureHandler` | One-off handler backed by a closure |

---

## URL Patterns

Path templates use `:paramName` for dynamic segments and `*` for wildcards:

```
"product/:productId"                → myapp://product/abc123
"store/:storeId/product/:productId" → myapp://store/s1/product/p99
"settings/:section"                 → myapp://settings/notifications
"home"                              → myapp://home
"*"                                 → matches anything (use as fallback)
```

Presentation hints can be attached to URLs with reserved query parameters:

```swift
let url = RouteRegistry("store/product/:productId")
    .builder(scheme: "myapp")
    .set("productId", "123")
    .presentation(.present)
    .build()
// myapp://store/product/123?dk_presentation=present
```

Supported values:

```
dk_presentation=automatic|push|present|fullScreen|setRoot|selectTab
dk_tab=2
dk_animated=true|false
```

---

## Micro-App Registration

The app shell should own one `DeeplinkManager`. Each micro app should own its routes, handlers, and navigation for its own screens.

```swift
// MainApp/App.swift
import DeeplinkKit
import StoreFeature
import ProfileFeature

let deeplinkManager = DeeplinkBuilder()
    .schemes(["myapp"])
    .universalLinkHosts(["app.example.com"])
    .modules([
        StoreDeeplinkModule(navigator: storeNavigator),
        ProfileDeeplinkModule(navigator: profileNavigator)
    ])
    .build(into: DeeplinkManager())

deeplinkManager.markReady()
```

```swift
// StoreFeature/StoreDeeplinks.swift
import DeeplinkKit

public enum StoreDeeplinks {
    public static let productDetail = RouteRegistry("store/product/:productId")
    public static let category = RouteRegistry("store/category/:slug")
}
```

```swift
// StoreFeature/StoreDeeplinkModule.swift
import DeeplinkKit

public struct StoreDeeplinkModule: DeeplinkModule {
    public let moduleID = "store"

    private let navigator: StoreNavigating

    public init(navigator: StoreNavigating) {
        self.navigator = navigator
    }

    public var deeplinkRoutes: [DeeplinkRouteDefinition] {
        [
            DeeplinkRouteDefinition(
                moduleID: moduleID,
                pattern: StoreDeeplinks.productDetail.template,
                handler: ProductDeeplinkHandler(navigator: navigator)
            )
        ]
    }
}
```

```swift
// StoreFeature/ProductDeeplinkHandler.swift
import DeeplinkKit

final class ProductDeeplinkHandler: DeeplinkHandling {
    let supportedPatterns = [StoreDeeplinks.productDetail.template]

    private let navigator: StoreNavigating

    init(navigator: StoreNavigating) {
        self.navigator = navigator
    }

    func handle(context: DeeplinkContext) async throws {
        guard let productId = context.resolvedRoute?.pathParams["productId"] else {
            throw DeeplinkError.missingParameter("productId")
        }

        await navigator.openProduct(
            id: productId,
            presentationStyle: context.options.presentationStyle,
            animated: context.options.animated
        )
    }
}
```

Cross-module navigation should use route contracts, not direct screen imports:

```swift
// StoreFeature opens ProfileFeature through DeeplinkKit
deeplinkOpener.open(
    ProfileDeeplinks.detail,
    parameters: ["userId": sellerId],
    options: .init(presentationStyle: .push),
    scheme: "myapp"
)
```

---

## Module Navigation Examples

UIKit modules can choose presentation based on `context.options`:

```swift
public final class UIKitStoreNavigator: StoreNavigating {
    private weak var navigationController: UINavigationController?

    public func openProduct(
        id: String,
        presentationStyle: DeeplinkPresentationStyle,
        animated: Bool
    ) async {
        await MainActor.run {
            let viewController = ProductViewController(productID: id)

            switch presentationStyle {
            case .automatic, .push:
                navigationController?.pushViewController(viewController, animated: animated)
            case .present:
                navigationController?.present(viewController, animated: animated)
            case .fullScreen:
                viewController.modalPresentationStyle = .fullScreen
                navigationController?.present(viewController, animated: animated)
            case .setRoot:
                navigationController?.setViewControllers([viewController], animated: animated)
            case .selectTab:
                break
            }
        }
    }
}
```

SwiftUI modules can map the same presentation style to `NavigationStack` and sheets:

```swift
@MainActor
public final class SwiftUIProfileNavigator: ObservableObject, ProfileNavigating {
    @Published var path: [ProfileRoute] = []
    @Published var presentedProfileID: String?

    public func openProfile(
        userId: String,
        presentationStyle: DeeplinkPresentationStyle,
        animated: Bool
    ) async {
        switch presentationStyle {
        case .automatic, .push:
            path.append(.detail(userId))
        case .present, .fullScreen:
            presentedProfileID = userId
        default:
            break
        }
    }
}
```

---

## UIKit Integration

```swift
// AppDelegate.swift
func application(_ app: UIApplication, open url: URL, options: ...) -> Bool {
    DeeplinkManager.shared.handle(openURL: url)
}

func application(_ app: UIApplication, continue userActivity: NSUserActivity, ...) -> Bool {
    DeeplinkManager.shared.handle(userActivity: userActivity)
}

func application(_ app: UIApplication, didReceiveRemoteNotification userInfo: ...) {
    DeeplinkManager.shared.handle(remoteNotification: userInfo)
}
```

---

## Testing

Use `dryRunMode` to test without triggering navigation:

```swift
var config = DeeplinkManager.Configuration()
config.dryRunMode = true

let manager = DeeplinkManager(configuration: config)
// configure parser & handlers...

let accepted = manager.process(url: URL(string: "myapp://product/123")!)
XCTAssertTrue(accepted)
```

Use `ClosureHandler` for assertion-based handler tests:

```swift
let expectation = expectation(description: "handled")
let handler = ClosureHandler(patterns: ["product/:id"]) { context in
    XCTAssertEqual(context.resolvedRoute?.pathParams["id"], "123")
    expectation.fulfill()
}
manager.register(handler: handler)
manager.process(url: URL(string: "myapp://product/123")!)
await fulfillment(of: [expectation], timeout: 2)
```

---

## License

MIT License. See LICENSE for details.

# ModularDeeplink
