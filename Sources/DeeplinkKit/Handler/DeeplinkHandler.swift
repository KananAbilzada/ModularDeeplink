// DeeplinkHandler.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// The protocol each feature module implements to handle deeplinks.
// This is the ONLY file a feature module needs to know about.

import Foundation

// MARK: - DeeplinkHandling Protocol

/// The single integration surface for feature modules.
/// Implement this protocol, call `DeeplinkManager.shared.register(handler:)`, done.
public protocol DeeplinkHandling: AnyObject, Sendable {

    // MARK: Required

    /// Higher values are tried first. Use 0–99 for default, 100–199 for priority, 200+ for system.
    var priority: Int { get }

    /// URL path patterns this handler supports.
    /// Use `:paramName` for dynamic segments, `*` for wildcards.
    /// Examples: ["product/:productId", "store/:storeId/product/:id"]
    var supportedPatterns: [String] { get }

    /// Perform navigation / state update for the given context.
    /// - Throws: `DeeplinkError` on failure.
    func handle(context: DeeplinkContext) async throws

    // MARK: Optional (have default implementations)

    /// Pre-check before `handle` is called. Return false to skip this handler.
    func canHandle(route: DeeplinkRoute) -> Bool

    /// Fallback URL to open if handling fails (e.g. web equivalent).
    var fallbackURL: URL? { get }

    /// Human-readable name for logging and debugging.
    var handlerName: String { get }
}

// MARK: - Default Implementations

public extension DeeplinkHandling {
    var priority: Int { 0 }
    var fallbackURL: URL? { nil }
    var handlerName: String { String(describing: type(of: self)) }

    func canHandle(route: DeeplinkRoute) -> Bool {
        supportedPatterns.contains { pattern in
            PatternMatcher.matches(route: route, pattern: pattern)
        }
    }
}

// MARK: - PatternMatcher (internal utility)

/// Matches a DeeplinkRoute against a pattern string like "product/:id"
enum PatternMatcher {
    static func matches(route: DeeplinkRoute, pattern: String) -> Bool {
        match(route: route, pattern: pattern) != nil
    }

    struct Match: Sendable {
        let pattern: String
        let identifier: String
        let pathParams: [String: String]
    }

    static func match(route: DeeplinkRoute, pattern: String) -> Match? {
        if route.matchedPattern == pattern {
            return Match(pattern: pattern, identifier: route.identifier, pathParams: route.pathParams)
        }

        let routeParts = route.identifier
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let patternParts = pattern
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if routeParts.count == patternParts.count {
            var pathParams = route.pathParams
            var identifierParts: [String] = []

            for (actual, template) in zip(routeParts, patternParts) {
                if template == "*" {
                    identifierParts.append(actual)
                    continue
                }
                if template.hasPrefix(":") {
                    pathParams[String(template.dropFirst())] = actual
                    continue
                }
                guard template.lowercased() == actual.lowercased() else { return nil }
                identifierParts.append(template)
            }

            let identifier = identifierParts.isEmpty ? route.identifier : identifierParts.joined(separator: "/")
            return Match(pattern: pattern, identifier: identifier, pathParams: pathParams)
        }

        let literalParts = patternParts.filter { !$0.hasPrefix(":") && $0 != "*" }
        guard !literalParts.isEmpty, literalParts.count == routeParts.count else { return nil }

        let literalMatch = zip(routeParts, literalParts).allSatisfy { actual, template in
            template.lowercased() == actual.lowercased()
        }
        guard literalMatch else { return nil }

        return Match(pattern: pattern, identifier: route.identifier, pathParams: route.pathParams)
    }

    static func patternsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let rhsParts = rhs.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard lhsParts.count == rhsParts.count else { return false }

        return zip(lhsParts, rhsParts).allSatisfy { left, right in
            if left == "*" || right == "*" { return true }
            if left.hasPrefix(":") || right.hasPrefix(":") { return true }
            return left.lowercased() == right.lowercased()
        }
    }
}

// MARK: - DeeplinkHandlerRegistration

/// Wraps a handler with its registration metadata.
struct DeeplinkHandlerRegistration: @unchecked Sendable {
    let handler: any DeeplinkHandling
    let patterns: [String]
    let moduleID: String?
    let registeredAt: Date

    init(handler: any DeeplinkHandling, patterns: [String], moduleID: String? = nil) {
        self.handler = handler
        self.patterns = patterns
        self.moduleID = moduleID
        self.registeredAt = Date()
    }
}
