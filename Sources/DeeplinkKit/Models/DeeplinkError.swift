// DeeplinkError.swift
// DeeplinkKit
//
// Typed error hierarchy for every failure mode in the deeplink pipeline.

import Foundation

// MARK: - DeeplinkError

/// Typed error hierarchy for every failure mode in the deeplink pipeline.
public enum DeeplinkError: Error, Sendable {

    // MARK: Parse Stage

    /// The URL could not be parsed by any registered parser
    case unresolvable(URL)

    /// The URL scheme is not registered / supported
    case unsupportedScheme(String)

    /// A required path or query parameter was missing
    case missingParameter(String)

    /// A parameter value had an unexpected type or format
    case invalidParameter(key: String, value: String)

    // MARK: Route Stage

    /// No handler was found for the parsed route
    case noHandlerFound(DeeplinkRoute)

    /// The route matched but the handler explicitly rejected it
    case handlerRejected(reason: String)

    // MARK: Middleware Stage

    /// A middleware intercepted and blocked the deeplink
    case blockedByMiddleware(name: String, reason: String)

    /// Authentication is required but the user is not authenticated
    case authenticationRequired(redirectURL: URL?)

    // MARK: Handler Stage

    /// The handler failed during navigation
    case navigationFailed(underlying: Error)

    /// Handler timed out
    case timeout(after: TimeInterval)

    // MARK: General

    /// An unexpected internal error
    case `internal`(String)

    // MARK: - LocalizedError conformance

    public var errorDescription: String {
        switch self {
        case .unresolvable(let url):
            return "Cannot resolve deeplink: \(url.absoluteString)"
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme)"
        case .missingParameter(let key):
            return "Required parameter '\(key)' is missing"
        case .invalidParameter(let key, let value):
            return "Parameter '\(key)' has invalid value: '\(value)'"
        case .noHandlerFound(let route):
            return "No handler registered for route: \(route.identifier)"
        case .handlerRejected(let reason):
            return "Handler rejected deeplink: \(reason)"
        case .blockedByMiddleware(let name, let reason):
            return "Middleware '\(name)' blocked deeplink: \(reason)"
        case .authenticationRequired:
            return "Authentication is required to open this deeplink"
        case .navigationFailed(let error):
            return "Navigation failed: \(error.localizedDescription)"
        case .timeout(let interval):
            return "Deeplink handling timed out after \(interval)s"
        case .internal(let message):
            return "Internal error: \(message)"
        }
    }
}
