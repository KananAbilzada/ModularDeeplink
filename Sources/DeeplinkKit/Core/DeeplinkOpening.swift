// DeeplinkOpening.swift
// DeeplinkKit
//
// Minimal abstraction for opening deeplink contracts from feature modules.

import Foundation

public protocol DeeplinkOpening: AnyObject, Sendable {
    @discardableResult
    func open(
        _ route: RouteRegistry,
        parameters: [String: String],
        query: [String: String],
        options: DeeplinkOpenOptions,
        scheme: String
    ) -> Bool
}

public extension DeeplinkOpening {
    @discardableResult
    func open(
        _ route: RouteRegistry,
        parameters: [String: String] = [:],
        options: DeeplinkOpenOptions = .init(),
        scheme: String
    ) -> Bool {
        open(route, parameters: parameters, query: [:], options: options, scheme: scheme)
    }
}

extension DeeplinkManager: DeeplinkOpening {}
