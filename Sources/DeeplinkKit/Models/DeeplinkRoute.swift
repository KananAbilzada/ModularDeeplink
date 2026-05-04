// DeeplinkRoute.swift
// DeeplinkKit
//
// Typed representation of a parsed deeplink URL.
// Produced by DeeplinkParser, consumed by DeeplinkRouter and DeeplinkHandlers.

import Foundation

// MARK: - DeeplinkRoute

/// A fully parsed, typed representation of a deeplink URL.
/// Immutable value type produced by any `DeeplinkParsing` implementation.
public struct DeeplinkRoute: Sendable, Equatable {

    // MARK: Properties

    /// Normalized route identifier, e.g. "product/detail" or "profile/settings"
    public let identifier: String

    /// The template that resolved this route, e.g. "product/:productId".
    public let matchedPattern: String?

    /// Extracted path parameters, e.g. ["productId": "abc123"]
    public let pathParams: [String: String]

    /// Decoded query parameters, e.g. ["ref": "email", "tab": "reviews"]
    public let queryParams: [String: String]

    /// URL fragment (after #), if present
    public let fragment: String?

    /// The raw URL before parsing
    public let rawURL: URL

    /// The URL scheme (custom or https)
    public let scheme: String

    /// The host component
    public let host: String

    // MARK: Init

    public init(
        identifier: String,
        matchedPattern: String? = nil,
        pathParams: [String: String] = [:],
        queryParams: [String: String] = [:],
        fragment: String? = nil,
        rawURL: URL,
        scheme: String,
        host: String
    ) {
        self.identifier = identifier
        self.matchedPattern = matchedPattern
        self.pathParams = pathParams
        self.queryParams = queryParams
        self.fragment = fragment
        self.rawURL = rawURL
        self.scheme = scheme
        self.host = host
    }

    // MARK: - Convenience accessors

    /// Returns a path param value, casting to the desired type if possible.
    public func pathParam<T: LosslessStringConvertible>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let raw = pathParams[key] else { return nil }
        return T(raw)
    }

    /// Returns a query param value, casting to the desired type if possible.
    public func queryParam<T: LosslessStringConvertible>(_ key: String, as type: T.Type = T.self) -> T? {
        guard let raw = queryParams[key] else { return nil }
        return T(raw)
    }

    /// Returns true if the route identifier matches the given pattern prefix.
    public func matches(prefix: String) -> Bool {
        identifier.hasPrefix(prefix)
    }
}

// MARK: - CustomDebugStringConvertible

extension DeeplinkRoute: CustomDebugStringConvertible {
    public var debugDescription: String {
        var parts = ["DeeplinkRoute(\(identifier))"]
        if !pathParams.isEmpty { parts.append("path:\(pathParams)") }
        if !queryParams.isEmpty { parts.append("query:\(queryParams)") }
        if let fragment { parts.append("fragment:\(fragment)") }
        return parts.joined(separator: " ")
    }
}
