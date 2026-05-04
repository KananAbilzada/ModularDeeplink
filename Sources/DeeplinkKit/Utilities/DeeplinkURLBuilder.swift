// DeeplinkURLBuilder.swift
// DeeplinkKit
//
// Reverse routing: programmatically construct deeplink URLs from
// route identifiers and parameters. Keeps URL formats in one place.

import Foundation

// MARK: - DeeplinkURLBuilder

/// Constructs deeplink URLs from route identifiers and parameters.
/// Use this instead of hardcoding URL strings throughout the codebase.
///
/// Usage:
/// ```swift
/// let url = DeeplinkURLBuilder(scheme: "myapp")
///     .route("product/:productId")
///     .set("productId", "abc123")
///     .query("ref", "email")
///     .query("tab", "reviews")
///     .build()
/// // → myapp://product/abc123?ref=email&tab=reviews
/// ```
public struct DeeplinkURLBuilder {

    // MARK: - Properties

    private let scheme: String
    private let host: String
    private var routeTemplate: String = ""
    private var pathParams: [String: String] = [:]
    private var queryItems: [(String, String)] = []
    private var fragment: String?

    // MARK: - Init

    /// - Parameters:
    ///   - scheme: URL scheme, e.g. `"myapp"` or `"https"`
    ///   - host: Optional host component. For custom schemes this is often empty.
    ///           For universal links use your domain, e.g. `"app.example.com"`.
    public init(scheme: String, host: String = "") {
        self.scheme = scheme
        self.host = host
    }

    // MARK: - Builder Methods (return new copy — value semantics)

    /// Set the route template, e.g. `"product/:productId"`.
    public func route(_ template: String) -> DeeplinkURLBuilder {
        var copy = self
        copy.routeTemplate = template
        return copy
    }

    /// Bind a path parameter.
    public func set(_ key: String, _ value: String) -> DeeplinkURLBuilder {
        var copy = self
        copy.pathParams[key] = value
        return copy
    }

    /// Bind a path parameter with a non-string convertible value.
    public func set<T: CustomStringConvertible>(_ key: String, _ value: T) -> DeeplinkURLBuilder {
        set(key, value.description)
    }

    /// Append a query parameter.
    public func query(_ key: String, _ value: String) -> DeeplinkURLBuilder {
        var copy = self
        copy.queryItems.append((key, value))
        return copy
    }

    /// Append a query parameter with a non-string convertible value.
    public func query<T: CustomStringConvertible>(_ key: String, _ value: T) -> DeeplinkURLBuilder {
        query(key, value.description)
    }

    /// Append multiple query parameters from a dictionary.
    public func queryParams(_ params: [String: String]) -> DeeplinkURLBuilder {
        var copy = self
        params.sorted(by: { $0.key < $1.key }).forEach { copy.queryItems.append(($0.key, $0.value)) }
        return copy
    }

    /// Set the URL fragment (after `#`).
    public func fragment(_ value: String) -> DeeplinkURLBuilder {
        var copy = self
        copy.fragment = value
        return copy
    }

    // MARK: - Build

    /// Construct the final URL by substituting path parameters into the template.
    /// - Returns: A fully-formed `URL`, or `nil` if construction fails.
    public func build() -> URL? {
        let resolvedPath = resolvePath()

        var components = URLComponents()
        components.scheme = scheme
        if host.isEmpty, scheme != "http", scheme != "https" {
            components.host = ""
        } else {
            components.host = host.isEmpty ? nil : host
        }
        components.path = resolvedPath.hasPrefix("/") ? resolvedPath : "/\(resolvedPath)"

        if !queryItems.isEmpty {
            components.queryItems = queryItems.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        components.fragment = fragment

        return components.url
    }

    /// Construct the final URL, throwing a `DeeplinkError` on failure.
    public func buildThrowing() throws -> URL {
        guard let url = build() else {
            throw DeeplinkError.internal("DeeplinkURLBuilder failed to construct URL from template: '\(routeTemplate)'")
        }
        return url
    }

    // MARK: - Private

    private func resolvePath() -> String {
        var segments: [String] = routeTemplate
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        segments = segments.map { segment in
            if segment.hasPrefix(":") {
                let key = String(segment.dropFirst())
                return pathParams[key] ?? segment // leave placeholder if not bound
            }
            return segment
        }

        return segments.joined(separator: "/")
    }
}

// MARK: - RouteRegistry (for discoverability)

/// A registry of named route templates. Centralise all your URL patterns here
/// so every module builds URLs from the same source of truth.
///
/// Usage:
/// ```swift
/// extension RouteRegistry {
///     static let productDetail = RouteRegistry("product/:productId")
///     static let profileSettings = RouteRegistry("profile/:userId/settings")
/// }
///
/// let url = RouteRegistry.productDetail
///     .builder(scheme: "myapp")
///     .set("productId", "abc123")
///     .build()
/// ```
public struct RouteRegistry {

    public let template: String

    public init(_ template: String) {
        self.template = template
    }

    /// Returns a pre-configured `DeeplinkURLBuilder` for this route.
    public func builder(scheme: String, host: String = "") -> DeeplinkURLBuilder {
        DeeplinkURLBuilder(scheme: scheme, host: host).route(template)
    }
}
