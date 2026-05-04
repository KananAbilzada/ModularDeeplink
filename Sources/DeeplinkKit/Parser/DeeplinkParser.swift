// DeeplinkParser.swift
// DeeplinkKit
//
// Protocol + concrete implementations for URL → DeeplinkRoute transformation.
// Uses a Chain-of-Responsibility pattern: parsers are tried in order.

import Foundation

// MARK: - DeeplinkParsing Protocol

/// Stateless transformer: URL in, typed DeeplinkRoute out.
/// Implement this protocol to support custom URL formats or schemes.
public protocol DeeplinkParsing: Sendable {
    /// Attempt to parse the given URL.
    /// - Returns: `.success(route)` on match, `.failure` to pass to next parser.
    func parse(url: URL) -> Result<DeeplinkRoute, DeeplinkError>

    /// Optional set of schemes this parser handles. Used for quick pre-filtering.
    var supportedSchemes: Set<String> { get }
}

public extension DeeplinkParsing {
    var supportedSchemes: Set<String> { [] }
}

// MARK: - CompositeParser

/// Chain-of-responsibility parser.
/// Tries each registered parser in order; returns first success.
public final class CompositeParser: DeeplinkParsing, @unchecked Sendable {

    private let parsers: [DeeplinkParsing]

    public init(parsers: [DeeplinkParsing]) {
        self.parsers = parsers
    }

    public var supportedSchemes: Set<String> {
        parsers.reduce(into: Set<String>()) { $0.formUnion($1.supportedSchemes) }
    }

    public func parse(url: URL) -> Result<DeeplinkRoute, DeeplinkError> {
        let scheme = url.scheme ?? ""
        let relevantParsers = parsers.filter {
            $0.supportedSchemes.isEmpty || $0.supportedSchemes.contains(scheme)
        }
        for parser in relevantParsers {
            let result = parser.parse(url: url)
            if case .success = result { return result }
        }
        return .failure(.unresolvable(url))
    }
}

// MARK: - StandardURLParser

/// Default parser handling both custom schemes and universal (https) links.
/// Path segments become the route identifier; params are extracted automatically.
///
/// Examples:
///   myapp://product/abc123?ref=email  →  identifier: "product", pathParams: ["id": "abc123"]
///   https://app.example.com/profile/42/settings  →  identifier: "profile/settings", pathParams: ["userId": "42"]
public final class StandardURLParser: DeeplinkParsing, @unchecked Sendable {

    public let supportedSchemes: Set<String>

    /// Route templates: ["product/:productId", "profile/:userId/settings"]
    private let templates: [RouteTemplate]

    public init(schemes: Set<String>, templates: [String]) {
        self.supportedSchemes = schemes
        self.templates = templates.map(RouteTemplate.init)
    }

    public func parse(url: URL) -> Result<DeeplinkRoute, DeeplinkError> {
        guard let scheme = url.scheme, supportedSchemes.contains(scheme) else {
            return .failure(.unsupportedScheme(url.scheme ?? ""))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.unresolvable(url))
        }

        let host = components.host ?? ""
        let rawPathSegments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let pathSegments: [String]
        if scheme == "http" || scheme == "https" {
            pathSegments = rawPathSegments
        } else {
            pathSegments = host.isEmpty ? rawPathSegments : [host] + rawPathSegments
        }

        let queryParams = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? [])
                .compactMap { item -> (String, String)? in
                    guard let value = item.value else { return nil }
                    return (item.name, value)
                }
        )

        let fragment = components.fragment

        // Try to match against registered templates
        for template in templates {
            if let (identifier, pathParams) = template.match(segments: pathSegments, host: host) {
                return .success(DeeplinkRoute(
                    identifier: identifier,
                    matchedPattern: template.pattern,
                    pathParams: pathParams,
                    queryParams: queryParams,
                    fragment: fragment,
                    rawURL: url,
                    scheme: scheme,
                    host: host
                ))
            }
        }

        // Fallback: build identifier from path segments directly. This lets feature-owned
        // handlers still match their own patterns even when the app shell did not
        // centralize templates in the parser.
        if !pathSegments.isEmpty {
            let identifier = pathSegments.joined(separator: "/")
            return .success(DeeplinkRoute(
                identifier: identifier,
                pathParams: [:],
                queryParams: queryParams,
                fragment: fragment,
                rawURL: url,
                scheme: scheme,
                host: host
            ))
        }

        // Host-only deeplink (e.g. myapp://home)
        if !host.isEmpty {
            return .success(DeeplinkRoute(
                identifier: host,
                pathParams: [:],
                queryParams: queryParams,
                fragment: fragment,
                rawURL: url,
                scheme: scheme,
                host: host
            ))
        }

        return .failure(.unresolvable(url))
    }
}

// MARK: - RouteTemplate (internal)

/// Represents a path template like "product/:productId" or "store/:storeId/product/:id"
struct RouteTemplate: Sendable {
    let pattern: String
    let segments: [TemplateSegment]
    let hostPattern: String?

    init(_ pattern: String) {
        // Support "host/path/pattern" style where first segment can be host
        let normalized = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        self.pattern = normalized
        self.segments = parts.map(TemplateSegment.init)
        self.hostPattern = nil
    }

    /// Attempt to match path segments against this template.
    /// Returns (identifier, pathParams) on success.
    func match(segments pathSegments: [String], host: String) -> (String, [String: String])? {
        guard segments.count == pathSegments.count else { return nil }

        var params: [String: String] = [:]
        var identifierParts: [String] = []

        for (template, actual) in zip(segments, pathSegments) {
            switch template {
            case .literal(let value):
                guard value.lowercased() == actual.lowercased() else { return nil }
                identifierParts.append(value)
            case .parameter(let name):
                params[name] = actual
                // Use the segment position name for identifier construction
                identifierParts.append(":\(name)")
            case .wildcard:
                identifierParts.append("*")
            }
        }

        // Build a clean identifier from literal segments only
        let cleanIdentifier = segments
            .compactMap { seg -> String? in
                if case .literal(let v) = seg { return v }
                return nil
            }
            .joined(separator: "/")

        return (cleanIdentifier.isEmpty ? identifierParts.joined(separator: "/") : cleanIdentifier, params)
    }
}

enum TemplateSegment: Sendable {
    case literal(String)
    case parameter(String)  // :paramName
    case wildcard           // *

    init(_ raw: String) {
        if raw.hasPrefix(":") {
            self = .parameter(String(raw.dropFirst()))
        } else if raw == "*" {
            self = .wildcard
        } else {
            self = .literal(raw)
        }
    }
}
