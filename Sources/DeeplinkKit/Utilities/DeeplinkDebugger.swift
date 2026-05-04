// DeeplinkKit
//
// Debug utilities: route inspection, dry-run firing, registered handler dump.
// Compile only in DEBUG builds by wrapping call sites in #if DEBUG.

import Foundation

// MARK: - DeeplinkDebugger

/// Development-only helper for inspecting and testing deeplink routes.
/// Wrap all usage in `#if DEBUG` in your app code.
public final class DeeplinkDebugger: Sendable {

    private let manager: DeeplinkManager
    private let parser: any DeeplinkParsing

    public init(manager: DeeplinkManager = .shared, parser: any DeeplinkParsing) {
        self.manager = manager
        self.parser = parser
    }

    // MARK: - Inspection

    /// Parse a URL string and pretty-print what would be resolved.
    /// Does NOT dispatch to any handler.
    @discardableResult
    public func inspect(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "❌ Invalid URL: \(urlString)"
        }

        switch parser.parse(url: url) {
        case .success(let route):
            var lines = [
                "✅ Parsed Successfully",
                "   URL:        \(url.absoluteString)",
                "   Identifier: \(route.identifier)",
                "   Scheme:     \(route.scheme)",
                "   Host:       \(route.host)",
            ]
            if !route.pathParams.isEmpty {
                lines.append("   Path Params:")
                route.pathParams.sorted(by: { $0.key < $1.key }).forEach {
                    lines.append("     • \($0.key) = \($0.value)")
                }
            }
            if !route.queryParams.isEmpty {
                lines.append("   Query Params:")
                route.queryParams.sorted(by: { $0.key < $1.key }).forEach {
                    lines.append("     • \($0.key) = \($0.value)")
                }
            }
            if let fragment = route.fragment {
                lines.append("   Fragment:   \(fragment)")
            }
            let output = lines.joined(separator: "\n")
            print(output)
            return output

        case .failure(let error):
            let output = "❌ Parse failed: \(error.errorDescription)"
            print(output)
            return output
        }
    }

    /// Fire a deeplink URL directly, bypassing middleware.
    /// Useful for QA and manual testing on device.
    
    public func fire(_ urlString: String, source: DeeplinkSource = .programmatic) {
        guard let url = URL(string: urlString) else {
            print("❌ [Debugger] Invalid URL: \(urlString)")
            return
        }
        var ctx = DeeplinkContext(url: url, source: source)
        ctx.bypassMiddleware = true
        print("🔥 [Debugger] Firing: \(urlString)")
        manager.processContext(ctx)
    }

    /// Simulate a push notification deeplink.
    
    public func simulatePush(urlString: String, extraPayload: [String: String] = [:]) {
        guard let url = URL(string: urlString) else { return }
        var payload = extraPayload
        payload["deeplink_url"] = urlString
        let ctx = DeeplinkContext(url: url, source: .pushNotification(payload: payload))
        print("📲 [Debugger] Simulating push: \(urlString)")
        manager.processContext(ctx)
    }
}

// MARK: - DeeplinkRoute + Debug

public extension DeeplinkRoute {
    /// Human-readable debug summary.
    var debugSummary: String {
        var parts = ["Route(\(identifier))"]
        if !pathParams.isEmpty { parts.append("path=\(pathParams)") }
        if !queryParams.isEmpty { parts.append("query=\(queryParams)") }
        return parts.joined(separator: " ")
    }
}
