// DeeplinkRouteDefinition.swift
// DeeplinkKit
//
// Module-owned route declarations. Feature modules expose only their own
// definitions; the app shell registers modules without centralizing all paths.

import Foundation

// MARK: - DeeplinkRouteDefinition

/// A route declaration owned by one feature module.
public struct DeeplinkRouteDefinition: Sendable {
    public let moduleID: String
    public let pattern: String
    public let handler: any DeeplinkHandling

    public init(
        moduleID: String,
        pattern: String,
        handler: any DeeplinkHandling
    ) {
        self.moduleID = moduleID
        self.pattern = pattern
        self.handler = handler
    }
}

// MARK: - DeeplinkModule

/// Preferred micro-app registration interface.
///
/// Each feature module returns only its own route definitions. The app shell can
/// register modules without importing or enumerating every feature's route enum.
public protocol DeeplinkModule: DeeplinkRegistrable {
    var moduleID: String { get }
    var deeplinkRoutes: [DeeplinkRouteDefinition] { get }
}

public extension DeeplinkModule {
    func registerDeeplinks(in manager: DeeplinkManager) {
        manager.register(moduleID: moduleID, routes: deeplinkRoutes)
    }
}
