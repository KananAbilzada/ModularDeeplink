// DeeplinkManager.swift
// DeeplinkKit
//
// The single orchestrator and public entry point.
// Owns the full pipeline: Context → Parse → Middleware → Route → Handle.
// Call process(url:source:) from AppDelegate / SceneDelegate.

import Foundation

// MARK: - DeeplinkManager

/// Central orchestrator for the deeplink system.
/// One shared instance; configure once at app launch.
public final class DeeplinkManager: @unchecked Sendable {

    // MARK: - Shared Instance

    public static let shared = DeeplinkManager()

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Whether to queue deeplinks received before `markReady()`. Default: true.
        public var enableColdStartQueue: Bool = true

        /// Maximum links to hold in the cold-start queue. Default: 10.
        public var coldStartQueueLimit: Int = 10

        /// If true, process(url:) returns immediately without dispatching. Useful for tests.
        public var dryRunMode: Bool = false

        /// Timeout for a single handler. Default: 10 seconds.
        public var handlerTimeout: TimeInterval = 10.0

        public init() {}
    }

    // MARK: - Dependencies

    private var parser: any DeeplinkParsing
    private let router: DeeplinkRouter
    private var middleware: [any DeeplinkMiddleware] = []
    private var moduleRegistrations: [any DeeplinkRegistrable] = []
    public var configuration: Configuration

    // MARK: - Cold Start Queue

    private var pendingQueue: [DeeplinkContext] = []
    private var isReady: Bool = false
    private let lock = NSLock()

    // MARK: - Event Callbacks

    public var onSuccess: ((DeeplinkContext) -> Void)?
    public var onError: ((DeeplinkContext, Error) -> Void)?
    public var onUnhandled: ((URL) -> Void)?

    // MARK: - Init

    public init(
        parser: (any DeeplinkParsing)? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.parser = parser ?? CompositeParser(parsers: [])
        self.router = DeeplinkRouter()
        self.configuration = configuration
    }

    // MARK: - Setup

    /// Configure the parser. Call during app launch before any deeplinks arrive.
    public func configure(parser: any DeeplinkParsing) {
        self.parser = parser
    }

    /// Add a middleware to the chain. Order matters — added in call order.
    public func use(_ middleware: any DeeplinkMiddleware) {
        self.middleware.append(middleware)
    }

    /// Replace the entire middleware stack.
    public func setMiddleware(_ middleware: [any DeeplinkMiddleware]) {
        self.middleware = middleware
    }
    /// Register a handler directly.
    public func register(handler: any DeeplinkHandling) {
        router.register(handler)
    }

    /// Register module-owned route definitions. Duplicate or ambiguous patterns
    /// are rejected so feature modules cannot accidentally take another
    /// module's route.
    public func register(moduleID: String, routes: [DeeplinkRouteDefinition]) {
        for route in routes {
            guard route.moduleID == moduleID else {
                DeeplinkLogger.log(.error, "[Registry] Route '\(route.pattern)' declares module '\(route.moduleID)' but was registered by '\(moduleID)'")
                continue
            }
            guard !router.hasPattern(route.pattern) else {
                DeeplinkLogger.log(.error, "[Registry] Duplicate deeplink route '\(route.pattern)' ignored for module '\(moduleID)'")
                continue
            }
            guard !router.hasAmbiguousPattern(route.pattern) else {
                DeeplinkLogger.log(.error, "[Registry] Ambiguous deeplink route '\(route.pattern)' ignored for module '\(moduleID)'")
                continue
            }
            router.register(route.handler, patterns: [route.pattern], moduleID: moduleID)
        }
    }

    /// Register a catch-all fallback handler.
    public func registerFallback(handler: any DeeplinkHandling) {
        router.registerFallback(handler)
    }

    /// Register all handlers from a module via the DeeplinkRegistrable protocol.
    public func registerModule(_ module: any DeeplinkRegistrable) {
        module.registerDeeplinks(in: self)
        moduleRegistrations.append(module)
    }

    /// Register multiple modules at once (typically called in AppDelegate).
    public func registerModules(_ modules: [any DeeplinkRegistrable]) {
        modules.forEach { registerModule($0) }
    }

    // MARK: - Readiness

    /// Call this when the app's root navigation is fully initialized
    /// and ready to handle navigation. Drains the cold-start queue.
    public func markReady() {
        lock.lock()
        guard !isReady else { lock.unlock(); return }
        isReady = true
        let queued = pendingQueue
        pendingQueue.removeAll()
        lock.unlock()

        DeeplinkLogger.log(.info, "DeeplinkManager ready. Draining \(queued.count) queued link(s).")
        queued.forEach { ctx in
            Task { await executeWithContext(ctx) }
        }
    }

    // MARK: - Main Entry Points

    /// Process a URL from any source.
    /// - Returns: `true` if the URL was accepted for processing (does not guarantee handling).
    @discardableResult
    public func process(url: URL, source: DeeplinkSource = .unknown) -> Bool {
        let context = DeeplinkContext(url: url, source: source)
        return processContext(context)
    }

    /// Process a pre-built DeeplinkContext.
    @discardableResult
    public func processContext(_ context: DeeplinkContext) -> Bool {
        guard !configuration.dryRunMode else {
            DeeplinkLogger.log(.debug, "[DryRun] Would process: \(context.url.absoluteString)")
            return true
        }

        lock.lock()
        let ready = isReady
        if !ready && configuration.enableColdStartQueue {
            if pendingQueue.count < configuration.coldStartQueueLimit {
                pendingQueue.append(context)
                lock.unlock()
                DeeplinkLogger.log(.debug, "Queued (cold start): \(context.url.absoluteString)")
            } else {
                lock.unlock()
                DeeplinkLogger.log(.warning, "Cold start queue full. Dropping: \(context.url.absoluteString)")
            }
            return true
        }
        lock.unlock()

        Task { await executeWithContext(context) }
        return true
    }

    // MARK: - Pipeline Execution

    private func executeWithContext(_ context: DeeplinkContext) async {
        // 1. Parse
        var ctx = context
        switch parser.parse(url: ctx.url) {
        case .success(let route):
            ctx.resolvedRoute = route
        case .failure(let error):
            DeeplinkLogger.log(.error, "Parse failed for \(ctx.url): \(error.errorDescription)")
            onError?(ctx, error)
            onUnhandled?(ctx.url)
            return
        }

        // 2. Build pipeline and dispatch
        let activeMiddleware = ctx.bypassMiddleware ? [] : middleware
        let pipeline = MiddlewarePipeline(middleware: activeMiddleware)
        let routerRef = router
        let timeoutNanos = UInt64(configuration.handlerTimeout * 1_000_000_000)
        let timeoutInterval = configuration.handlerTimeout

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await pipeline.execute(context: ctx) { resolvedContext in
                        try await routerRef.dispatch(context: resolvedContext)
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    throw DeeplinkError.timeout(after: timeoutInterval)
                }
                // First task to finish wins; cancel the other
                if let result = await group.nextResult() {
                    group.cancelAll()
                    // Re-throw if the winning task was the timeout
                    if case .failure(let err) = result { throw err }
                }
                group.cancelAll()
            }
            onSuccess?(ctx)
        } catch {
            DeeplinkLogger.log(.error, "Pipeline error for \(ctx.url): \((error as? DeeplinkError)?.errorDescription ?? error.localizedDescription)")
            onError?(ctx, error)
        }
    }

    // MARK: - Utilities

    /// Test whether a URL would be routable without dispatching it.
    public func canProcess(url: URL) -> Bool {
        guard case .success(let route) = parser.parse(url: url) else { return false }
        return router.canRoute(route)
    }

    /// Get all registered handlers (for debugging).
    public var registeredHandlers: [any DeeplinkHandling] {
        router.allHandlers
    }

    /// Get registered route patterns owned by a module. Use for diagnostics
    /// inside a feature without exposing other modules' routes.
    public func registeredPatterns(moduleID: String) -> [String] {
        router.patterns(moduleID: moduleID)
    }
}

// MARK: - DeeplinkRegistrable

/// Modules conform to this protocol to self-register their handlers.
/// The only file a module needs to touch is its own conformance.
public protocol DeeplinkRegistrable {
    func registerDeeplinks(in manager: DeeplinkManager)
}
