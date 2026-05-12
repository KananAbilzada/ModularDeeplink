// DeeplinkRouter.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// Priority-based handler registry. Matches a resolved DeeplinkRoute to
// the best registered handler and dispatches. Thread-safe via NSLock.

import Foundation

// MARK: - DeeplinkRouter

/// Priority-ordered handler registry.
/// Thread-safe. Handles registration, lookup, and dispatch.
public final class DeeplinkRouter: @unchecked Sendable {

    // MARK: State

    private var registrations: [DeeplinkHandlerRegistration] = []
    private var fallbackHandler: (any DeeplinkHandling)?
    private let lock = NSLock()

    // MARK: Init

    public init() {}

    // MARK: - Registration

    /// Register a handler. Duplicate handler types are silently replaced.
    public func register(_ handler: any DeeplinkHandling) {
        lock.lock()
        defer { lock.unlock() }
        registrations.removeAll { type(of: $0.handler) == type(of: handler) }
        registrations.append(DeeplinkHandlerRegistration(handler: handler, patterns: handler.supportedPatterns))
        registrations.sort { $0.handler.priority > $1.handler.priority }
    }

    /// Register a handler for a constrained set of patterns owned by one module.
    public func register(_ handler: any DeeplinkHandling, patterns: [String], moduleID: String) {
        lock.lock()
        defer { lock.unlock() }
        registrations.append(DeeplinkHandlerRegistration(handler: handler, patterns: patterns, moduleID: moduleID))
        registrations.sort { $0.handler.priority > $1.handler.priority }
    }

    /// Register multiple handlers at once.
    public func register(_ handlers: [any DeeplinkHandling]) {
        handlers.forEach { register($0) }
    }

    /// Register a catch-all fallback handler.
    public func registerFallback(_ handler: any DeeplinkHandling) {
        lock.lock()
        defer { lock.unlock() }
        fallbackHandler = handler
    }

    /// Remove a handler by type.
    public func unregister<H: DeeplinkHandling>(_ handlerType: H.Type) {
        lock.lock()
        defer { lock.unlock() }
        registrations.removeAll { type(of: $0.handler) == handlerType }
    }

    // MARK: - Dispatch

    /// Find the best handler for the context and invoke it.
    public func dispatch(context: DeeplinkContext) async throws {
        guard let route = context.resolvedRoute else {
            throw DeeplinkError.internal("dispatch() called before route was resolved")
        }

        let selected = firstMatch(for: route)

        if let selected {
            var resolvedContext = context
            if let match = selected.match {
                resolvedContext.resolvedRoute = route.applying(match)
            }
            DeeplinkLogger.log(.debug, "[\(selected.handler.handlerName)] handling \(resolvedContext.resolvedRoute?.identifier ?? route.identifier)")
            try await selected.handler.handle(context: resolvedContext)
            return
        }

        let fallback = fallbackHandlerSnapshot()
        if let fb = fallback, fb.canHandle(route: route) {
            DeeplinkLogger.log(.debug, "[fallback] handling \(route.identifier)")
            try await fb.handle(context: context)
            return
        }

        throw DeeplinkError.noHandlerFound(route)
    }

    private func firstMatch(for route: DeeplinkRoute) -> (handler: any DeeplinkHandling, match: PatternMatcher.Match?)? {
        lock.lock()
        let snapshot = registrations
        lock.unlock()

        for registration in snapshot {
            let handler = registration.handler
            if let match = registration.patterns.compactMap({ PatternMatcher.match(route: route, pattern: $0) }).first {
                return (handler, match)
            }
            if handler.canHandle(route: route) {
                return (handler, nil)
            }
        }
        return nil
    }

    private func fallbackHandlerSnapshot() -> (any DeeplinkHandling)? {
        lock.lock()
        defer { lock.unlock() }
        return fallbackHandler
    }

    // MARK: - Introspection

    public var allHandlers: [any DeeplinkHandling] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.map(\.handler)
    }

    public func handlers(for route: DeeplinkRoute) -> [any DeeplinkHandling] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.filter { registration in
            registration.patterns.contains { PatternMatcher.matches(route: route, pattern: $0) } || registration.handler.canHandle(route: route)
        }.map(\.handler)
    }

    public func handlers(moduleID: String) -> [any DeeplinkHandling] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.filter { $0.moduleID == moduleID }.map(\.handler)
    }

    public func patterns(moduleID: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.filter { $0.moduleID == moduleID }.flatMap(\.patterns)
    }

    public var allPatterns: [String] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.flatMap(\.patterns)
    }

    public func owner(of pattern: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return registrations.first { $0.patterns.contains(pattern) }?.moduleID
    }

    public func hasPattern(_ pattern: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return registrations.contains { $0.patterns.contains(pattern) }
    }

    public func hasAmbiguousPattern(_ pattern: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return registrations.contains { registration in
            registration.patterns.contains { PatternMatcher.patternsOverlap($0, pattern) }
        }
    }

    public func canRoute(_ route: DeeplinkRoute) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return registrations.contains { registration in
            registration.patterns.contains { PatternMatcher.matches(route: route, pattern: $0) } || registration.handler.canHandle(route: route)
        }
    }
}

private extension DeeplinkRoute {
    func applying(_ match: PatternMatcher.Match) -> DeeplinkRoute {
        DeeplinkRoute(
            identifier: match.identifier,
            matchedPattern: match.pattern,
            pathParams: match.pathParams,
            queryParams: queryParams,
            fragment: fragment,
            rawURL: rawURL,
            scheme: scheme,
            host: host
        )
    }
}
