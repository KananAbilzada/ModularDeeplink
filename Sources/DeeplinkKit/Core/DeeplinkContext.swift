// DeeplinkContext.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// The immutable value type that flows through the entire deeplink pipeline.
// Every stage reads from and optionally transforms this context.

import Foundation

// MARK: - DeeplinkContext

/// Immutable context carrying all data needed for one deeplink lifecycle.
/// Thread-safe as a value type. Passed through middleware and handlers.
public struct DeeplinkContext: Sendable {

    // MARK: Properties

    /// The original raw URL that triggered this deeplink
    public let url: URL

    /// The source that triggered this deeplink (push, universal link, etc.)
    public let source: DeeplinkSource

    /// Snapshot of the user's authentication state at receipt time
    public let authState: AuthState

    /// Arbitrary key-value metadata (e.g. push notification payload extras)
    public let metadata: [String: String]

    /// Presentation hints for app navigation.
    public let options: DeeplinkOpenOptions

    /// Timestamp when this context was created
    public let receivedAt: Date

    /// Unique identifier for this deeplink invocation (for logging/analytics)
    public let traceID: String

    /// The resolved route after parsing. Set by the parser stage.
    public internal(set) var resolvedRoute: DeeplinkRoute?

    /// Whether this deeplink should skip middleware (e.g. internal test links)
    public var bypassMiddleware: Bool = false

    // MARK: Init

    public init(
        url: URL,
        source: DeeplinkSource,
        authState: AuthState = .unknown,
        metadata: [String: String] = [:],
        options: DeeplinkOpenOptions = .init(),
        receivedAt: Date = Date(),
        traceID: String = UUID().uuidString
    ) {
        self.url = url
        self.source = source
        self.authState = authState
        self.metadata = metadata
        self.options = options
        self.receivedAt = receivedAt
        self.traceID = traceID
    }
}

// MARK: - DeeplinkSource

/// Describes how a deeplink was triggered.
public enum DeeplinkSource: Sendable {
    /// Universal link (HTTPS) via UIApplicationDelegate / NSUserActivity
    case universalLink

    /// Custom URL scheme (e.g. myapp://...)
    case customScheme

    /// Triggered from a push notification payload
    case pushNotification(payload: [String: String])

    /// Home screen quick action shortcut
    case shortcutItem(type: String)

    /// Spotlight / Handoff via NSUserActivity
    case userActivity(activityType: String)

    /// iOS Widget link
    case widget

    /// Programmatic / internal call
    case programmatic

    /// Unknown / not determined
    case unknown

    // MARK: Computed

    public var description: String {
        switch self {
        case .universalLink:               return "universalLink"
        case .customScheme:                return "customScheme"
        case .pushNotification:            return "pushNotification"
        case .shortcutItem(let type):      return "shortcut(\(type))"
        case .userActivity(let type):      return "userActivity(\(type))"
        case .widget:                      return "widget"
        case .programmatic:                return "programmatic"
        case .unknown:                     return "unknown"
        }
    }
}

// MARK: - AuthState

/// Snapshot of authentication at deeplink receipt time.
public enum AuthState: Sendable {
    case authenticated(userID: String)
    case unauthenticated
    case unknown

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    public var userID: String? {
        if case .authenticated(let id) = self { return id }
        return nil
    }
}
