// DeeplinkOpenOptions.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// Typed presentation hints for deeplink handling.

import Foundation

// MARK: - DeeplinkPresentationStyle

public enum DeeplinkPresentationStyle: Sendable, Equatable {
    case automatic
    case push
    case present
    case fullScreen
    case setRoot
    case selectTab(Int)
}

// MARK: - DeeplinkOpenOptions

public struct DeeplinkOpenOptions: Sendable, Equatable {
    public static let presentationQueryKey = "dk_presentation"
    public static let tabQueryKey = "dk_tab"
    public static let animatedQueryKey = "dk_animated"

    public var presentationStyle: DeeplinkPresentationStyle
    public var animated: Bool

    public init(
        presentationStyle: DeeplinkPresentationStyle = .automatic,
        animated: Bool = true
    ) {
        self.presentationStyle = presentationStyle
        self.animated = animated
    }

    public init(url: URL, fallback: DeeplinkOpenOptions = .init()) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            self = fallback
            return
        }

        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        let style = Self.presentationStyle(
            from: query[Self.presentationQueryKey],
            tabValue: query[Self.tabQueryKey]
        ) ?? fallback.presentationStyle
        let animated = query[Self.animatedQueryKey].flatMap(Self.boolValue) ?? fallback.animated

        self.init(presentationStyle: style, animated: animated)
    }

    public var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: Self.presentationQueryKey, value: presentationStyle.queryValue)
        ]

        if !animated {
            items.append(URLQueryItem(name: Self.animatedQueryKey, value: "false"))
        }

        if case .selectTab(let index) = presentationStyle {
            items.append(URLQueryItem(name: Self.tabQueryKey, value: String(index)))
        }

        return items
    }

    private static func presentationStyle(from rawValue: String?, tabValue: String?) -> DeeplinkPresentationStyle? {
        guard let rawValue else { return nil }

        switch rawValue {
        case "automatic": return .automatic
        case "push": return .push
        case "present": return .present
        case "fullScreen": return .fullScreen
        case "setRoot": return .setRoot
        case "selectTab":
            guard let tabValue, let index = Int(tabValue) else { return .selectTab(0) }
            return .selectTab(index)
        default:
            return nil
        }
    }

    private static func boolValue(_ rawValue: String) -> Bool? {
        switch rawValue.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }
}

private extension DeeplinkPresentationStyle {
    var queryValue: String {
        switch self {
        case .automatic: return "automatic"
        case .push: return "push"
        case .present: return "present"
        case .fullScreen: return "fullScreen"
        case .setRoot: return "setRoot"
        case .selectTab: return "selectTab"
        }
    }
}
