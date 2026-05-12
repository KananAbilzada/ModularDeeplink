// DeeplinkMiddleware.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// Middleware intercepts the pipeline between Parse and Route stages.
// Chain pattern: each middleware calls `next` to continue, or throws to abort.

import Foundation

// MARK: - DeeplinkMiddleware Protocol

/// Intercept the deeplink pipeline. Modify context, gate on conditions,
/// or short-circuit by throwing without calling `next`.
public protocol DeeplinkMiddleware: Sendable {
    /// Human-readable name for logging.
    var middlewareName: String { get }

    /// Process the context. Call `next(context)` to continue, throw to abort.
    func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws
}

public extension DeeplinkMiddleware {
    var middlewareName: String { String(describing: type(of: self)) }
}

// MARK: - MiddlewarePipeline

/// Assembles a list of middleware into a single callable pipeline.
public struct MiddlewarePipeline: Sendable {

    private let middleware: [any DeeplinkMiddleware]

    public init(middleware: [any DeeplinkMiddleware]) {
        self.middleware = middleware
    }

    /// Execute the full middleware chain, then call `terminal` at the end.
    public func execute(
        context: DeeplinkContext,
        terminal: @Sendable @escaping (DeeplinkContext) async throws -> Void
    ) async throws {
        try await run(context: context, index: 0, terminal: terminal)
    }

    private func run(
        context: DeeplinkContext,
        index: Int,
        terminal: @Sendable @escaping (DeeplinkContext) async throws -> Void
    ) async throws {
        if index >= middleware.count {
            try await terminal(context)
            return
        }
        let current = middleware[index]
        try await current.intercept(context: context) { [self] nextContext in
            try await run(context: nextContext, index: index + 1, terminal: terminal)
        }
    }
}

// MARK: - Built-in Middleware

// ─────────────────────────────────────────────────────────────────────────────
// 1. Authentication Middleware
// ─────────────────────────────────────────────────────────────────────────────

/// Gates deeplinks that require authentication.
/// Redirects to login if the user is not authenticated.
public final class AuthMiddleware: DeeplinkMiddleware {

    public let middlewareName = "AuthMiddleware"

    /// Route identifiers (or prefixes) that require authentication.
    private let protectedRoutes: Set<String>

    /// Called when a protected route is accessed without authentication.
    /// Provide a URL to redirect to (e.g. your login deeplink).
    private let loginRedirectURL: URL?

    public init(protectedRoutes: Set<String>, loginRedirectURL: URL? = nil) {
        self.protectedRoutes = protectedRoutes
        self.loginRedirectURL = loginRedirectURL
    }

    public func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws {
        let routeID = context.resolvedRoute?.identifier ?? ""
        let isProtected = protectedRoutes.contains { protected in
            routeID == protected || routeID.hasPrefix(protected + "/")
        }

        if isProtected && !context.authState.isAuthenticated {
            DeeplinkLogger.log(.warning, "[Auth] Blocked protected route: \(routeID)")
            throw DeeplinkError.authenticationRequired(redirectURL: loginRedirectURL)
        }

        try await next(context)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Analytics Middleware
// ─────────────────────────────────────────────────────────────────────────────

/// Records each deeplink invocation. Fires before and after handling.
public final class AnalyticsMiddleware: DeeplinkMiddleware {

    public let middlewareName = "AnalyticsMiddleware"

    public typealias EventHandler = @Sendable (AnalyticsEvent) -> Void
    private let onEvent: EventHandler

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
    }

    public func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws {
        let start = Date()
        let event = AnalyticsEvent(
            traceID: context.traceID,
            url: context.url,
            source: context.source.description,
            routeIdentifier: context.resolvedRoute?.identifier,
            timestamp: start
        )
        onEvent(event)

        do {
            try await next(context)
            var completed = event
            completed.duration = Date().timeIntervalSince(start)
            completed.outcome = .success
            onEvent(completed)
        } catch {
            var failed = event
            failed.duration = Date().timeIntervalSince(start)
            failed.outcome = .failure(error)
            onEvent(failed)
            throw error
        }
    }
}

/// Analytics event produced by `AnalyticsMiddleware`.
public struct AnalyticsEvent: Sendable {
    public let traceID: String
    public let url: URL
    public let source: String
    public let routeIdentifier: String?
    public let timestamp: Date
    public var duration: TimeInterval?
    public var outcome: Outcome?

    public enum Outcome: Sendable {
        case success
        case failure(Error)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Feature Flag Middleware
// ─────────────────────────────────────────────────────────────────────────────

/// Blocks or redirects deeplinks based on feature flag state.
public final class FeatureFlagMiddleware: DeeplinkMiddleware {

    public let middlewareName = "FeatureFlagMiddleware"

    public typealias FlagChecker = @Sendable (String) async -> Bool

    /// Map of routeIdentifierPrefix → featureFlagKey
    private let routeToFlagMap: [String: String]

    /// Async closure that returns true if the flag is enabled.
    private let isFlagEnabled: FlagChecker

    /// Optional fallback URL when a route is gated by a disabled flag.
    private let fallbackURL: URL?

    public init(
        routeToFlagMap: [String: String],
        isFlagEnabled: @escaping FlagChecker,
        fallbackURL: URL? = nil
    ) {
        self.routeToFlagMap = routeToFlagMap
        self.isFlagEnabled = isFlagEnabled
        self.fallbackURL = fallbackURL
    }

    public func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws {
        let routeID = context.resolvedRoute?.identifier ?? ""

        for (routePrefix, flagKey) in routeToFlagMap {
            guard routeID == routePrefix || routeID.hasPrefix(routePrefix + "/") else { continue }

            let enabled = await isFlagEnabled(flagKey)
            if !enabled {
                DeeplinkLogger.log(.warning, "[FeatureFlag] Route '\(routeID)' gated by flag '\(flagKey)' (disabled)")
                throw DeeplinkError.blockedByMiddleware(
                    name: middlewareName,
                    reason: "Feature '\(flagKey)' is disabled"
                )
            }
        }

        try await next(context)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Logging Middleware
// ─────────────────────────────────────────────────────────────────────────────

/// Detailed request/response logging for debugging. Enable only in debug builds.
public final class LoggingMiddleware: DeeplinkMiddleware {

    public let middlewareName = "LoggingMiddleware"
    private let level: DeeplinkLogger.Level

    public init(level: DeeplinkLogger.Level = .debug) {
        self.level = level
    }

    public func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws {
        DeeplinkLogger.log(level, """
        ┌─ Deeplink ────────────────────────────────
        │ URL:    \(context.url.absoluteString)
        │ Source: \(context.source.description)
        │ Route:  \(context.resolvedRoute?.identifier ?? "unresolved")
        │ Trace:  \(context.traceID)
        └───────────────────────────────────────────
        """)

        let start = Date()
        do {
            try await next(context)
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(start) * 1000)
            DeeplinkLogger.log(level, "✓ Deeplink handled in \(elapsed)ms [\(context.traceID)]")
        } catch {
            DeeplinkLogger.log(.error, "✗ Deeplink failed: \(error) [\(context.traceID)]")
            throw error
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Rate Limiting Middleware
// ─────────────────────────────────────────────────────────────────────────────

/// Prevents the same deeplink from firing too rapidly (e.g. from push storms).
public final class RateLimitMiddleware: DeeplinkMiddleware, @unchecked Sendable {

    public let middlewareName = "RateLimitMiddleware"

    private let interval: TimeInterval
    private var lastFired: [String: Date] = [:]
    private let lock = NSLock()

    /// - Parameter interval: Minimum seconds between identical deeplinks. Default: 1.0s
    public init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    public func intercept(
        context: DeeplinkContext,
        next: @Sendable (DeeplinkContext) async throws -> Void
    ) async throws {
        let key = context.url.absoluteString
        if shouldThrottle(key: key) {
            DeeplinkLogger.log(.warning, "[RateLimit] Throttled: \(key)")
            throw DeeplinkError.blockedByMiddleware(name: middlewareName, reason: "Rate limit exceeded")
        }
        try await next(context)
    }

    private func shouldThrottle(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last = lastFired[key], Date().timeIntervalSince(last) < interval {
            return true
        }
        lastFired[key] = Date()
        return false
    }
}
