// ExampleHandlers.swift
// DeeplinkKit
//
// Reference implementations of DeeplinkHandling.
// Copy and adapt for your feature modules.
// These are NOT included in the framework itself — they are documentation/examples.

import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - WebFallbackHandler

/// Catch-all fallback handler that opens unmatched deeplinks in Safari / a web browser.
/// Register this as your fallback to ensure no deeplink is silently dropped.
public final class WebFallbackHandler: DeeplinkHandling {

    public let priority: Int = Int.min  // Always last
    public let supportedPatterns: [String] = ["*"]
    public let handlerName = "WebFallbackHandler"

    private let baseWebURL: URL?

    public init(baseWebURL: URL? = nil) {
        self.baseWebURL = baseWebURL
    }

    public func canHandle(route: DeeplinkRoute) -> Bool { true }

    public func handle(context: DeeplinkContext) async throws {
        let target: URL
        if let base = baseWebURL {
            // Convert custom scheme to https equivalent
            var components = URLComponents(url: context.url, resolvingAgainstBaseURL: false)
            components?.scheme = base.scheme
            components?.host = base.host
            target = components?.url ?? context.url
        } else {
            target = context.url
        }
        DeeplinkLogger.log(.info, "[WebFallback] Opening: \(target.absoluteString)")
        #if canImport(UIKit)
        await MainActor.run {
            UIApplication.shared.open(target)
        }
        #endif
    }
}

// MARK: - NoOpHandler

/// Silent no-op handler. Useful for swallowing specific routes in tests.
public final class NoOpHandler: DeeplinkHandling {
    public let priority: Int
    public let supportedPatterns: [String]
    public let handlerName: String

    public init(patterns: [String], priority: Int = 0, name: String = "NoOpHandler") {
        self.supportedPatterns = patterns
        self.priority = priority
        self.handlerName = name
    }

    public func handle(context: DeeplinkContext) async throws {
        DeeplinkLogger.log(.debug, "[NoOp] Swallowed: \(context.resolvedRoute?.identifier ?? context.url.absoluteString)")
    }
}

// MARK: - ClosureHandler

/// Quick handler backed by a closure. Great for one-off routes or tests.
///
/// Usage:
/// ```swift
/// let handler = ClosureHandler(patterns: ["home"]) { context in
///     print("Home route received: \(context.url)")
/// }
/// DeeplinkManager.shared.register(handler: handler)
/// ```
public final class ClosureHandler: DeeplinkHandling {
    public let priority: Int
    public let supportedPatterns: [String]
    public let handlerName: String
    public let fallbackURL: URL?

    private let closure: @Sendable (DeeplinkContext) async throws -> Void

    public init(
        patterns: [String],
        priority: Int = 0,
        name: String = "ClosureHandler",
        fallbackURL: URL? = nil,
        handler: @escaping @Sendable (DeeplinkContext) async throws -> Void
    ) {
        self.supportedPatterns = patterns
        self.priority = priority
        self.handlerName = name
        self.fallbackURL = fallbackURL
        self.closure = handler
    }

    public func handle(context: DeeplinkContext) async throws {
        try await closure(context)
    }
}
