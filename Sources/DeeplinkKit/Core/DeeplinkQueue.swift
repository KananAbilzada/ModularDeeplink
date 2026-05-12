// DeeplinkQueue.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// Thread-safe FIFO queue for buffering deeplinks during cold start.
// Optionally persists the last-received URL across app launches.

import Foundation

// MARK: - DeeplinkQueue

/// Thread-safe FIFO buffer for deeplinks received before the app is ready.
/// Automatically drains when `drain()` is called.
final class DeeplinkQueue: @unchecked Sendable {

    // MARK: - Configuration

    struct Configuration {
        /// Maximum items to hold. Oldest are dropped when full.
        var capacity: Int = 10

        /// If true, the most recent URL is persisted to UserDefaults
        /// and re-enqueued on next cold launch (useful for killed-app scenarios).
        var persistLastURL: Bool = false

        /// UserDefaults key for persistence.
        var persistenceKey: String = "DeeplinkKit.pendingURL"
    }

    // MARK: - State

    private var items: [DeeplinkContext] = []
    private let lock = NSLock()
    private let config: Configuration

    // MARK: - Init

    init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    // MARK: - Enqueue

    /// Add a context to the queue. Drops oldest if over capacity.
    func enqueue(_ context: DeeplinkContext) {
        lock.lock()
        defer { lock.unlock() }

        if items.count >= config.capacity {
            DeeplinkLogger.log(.warning, "[Queue] Capacity (\(config.capacity)) reached. Dropping oldest.")
            items.removeFirst()
        }
        items.append(context)

        if config.persistLastURL {
            UserDefaults.standard.set(context.url.absoluteString, forKey: config.persistenceKey)
        }

        DeeplinkLogger.log(.debug, "[Queue] Enqueued \(context.url.absoluteString). Depth: \(items.count)")
    }

    // MARK: - Drain

    /// Remove and return all queued contexts. Thread-safe.
    func drain() -> [DeeplinkContext] {
        lock.lock()
        defer { lock.unlock() }

        let drained = items
        items.removeAll()

        if config.persistLastURL {
            UserDefaults.standard.removeObject(forKey: config.persistenceKey)
        }

        DeeplinkLogger.log(.info, "[Queue] Drained \(drained.count) pending deeplink(s).")
        return drained
    }

    // MARK: - Persistence

    /// Returns a persisted context from a previous launch, if any.
    /// Call during app launch to recover deeplinks from killed-app scenarios.
    func recoverPersistedContext() -> DeeplinkContext? {
        guard config.persistLastURL,
              let urlString = UserDefaults.standard.string(forKey: config.persistenceKey),
              let url = URL(string: urlString) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: config.persistenceKey)
        DeeplinkLogger.log(.info, "[Queue] Recovered persisted deeplink: \(urlString)")
        return DeeplinkContext(url: url, source: .programmatic)
    }

    // MARK: - Inspection

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    var isEmpty: Bool { count == 0 }
}
