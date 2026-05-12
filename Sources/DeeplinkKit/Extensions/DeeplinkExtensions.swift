// DeeplinkExtensions.swift
// DeeplinkKit
//
// Convenience extensions for UIKit / SwiftUI app lifecycle integration.
// Drop these call sites into your AppDelegate or SceneDelegate.

import Foundation

#if canImport(UIKit)
import UIKit

// MARK: - UIApplicationDelegate Helpers

public extension DeeplinkManager {

    /// Handle `application(_:open:options:)` — custom scheme URLs.
    /// Returns `true` if the URL was accepted.
    @discardableResult
    func handle(openURL url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        let source: DeeplinkSource = .customScheme
        return process(url: url, source: source)
    }

    /// Handle `application(_:continue:restorationHandler:)` — universal links & Spotlight.
    /// Returns `true` if the activity was accepted.
    @discardableResult
    func handle(userActivity: NSUserActivity) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL {
            return process(url: url, source: .universalLink)
        }
        // Spotlight / Handoff
        if let url = userActivity.userInfo?["url"] as? URL {
            return process(url: url, source: .userActivity(activityType: userActivity.activityType))
        }
        return false
    }

    /// Handle remote notification that carries a deeplink URL.
    func handle(remoteNotification userInfo: [AnyHashable: Any]) {
        // Look for "deeplink_url" key in the payload (customize this key as needed)
        let candidates = ["deeplink_url", "url", "link", "deep_link"]
        for key in candidates {
            if let urlString = userInfo[key] as? String, let url = URL(string: urlString) {
                let payload = userInfo.reduce(into: [String: String]()) { result, item in
                    guard let value = item.value as? String else { return }
                    result[String(describing: item.key)] = value
                }
                _ = process(url: url, source: .pushNotification(payload: payload))
                return
            }
        }
    }

    /// Handle `application(_:performActionFor:completionHandler:)` — home screen shortcuts.
    func handle(shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        guard let urlString = shortcutItem.userInfo?["url"] as? String,
              let url = URL(string: urlString) else {
            completionHandler(false)
            return
        }
        let accepted = process(url: url, source: .shortcutItem(type: shortcutItem.type))
        completionHandler(accepted)
    }
}

// MARK: - UIScene / SceneDelegate Helpers

@available(iOS 13.0, *)
public extension DeeplinkManager {

    /// Handle `scene(_:willConnectTo:options:)` — launch deeplink.
    func handleSceneConnection(options: UIScene.ConnectionOptions) {
        if let activity = options.userActivities.first {
            handle(userActivity: activity)
        } else if let urlContext = options.urlContexts.first {
            handle(openURL: urlContext.url)
        }
    }

    /// Handle `scene(_:openURLContexts:)`.
    func handle(urlContexts: Set<UIOpenURLContext>) {
        for context in urlContexts {
            handle(openURL: context.url)
        }
    }

    /// Handle `scene(_:continue:)` — universal link while app is running.
    @discardableResult
    func handle(continueUserActivity activity: NSUserActivity) -> Bool {
        handle(userActivity: activity)
    }
}

#endif

// MARK: - SwiftUI Integration

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
public extension View {
    /// Attaches DeeplinkKit handling to a SwiftUI view hierarchy.
    ///
    /// Usage:
    /// ```swift
    /// ContentView()
    ///     .handlesDeeplinks()
    /// ```
    func handlesDeeplinks(manager: DeeplinkManager = .shared) -> some View {
        self
            .onOpenURL { url in
                manager.process(url: url, source: .universalLink)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    manager.process(url: url, source: .universalLink)
                }
            }
    }
}
#endif
