// DeeplinkBuilder.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// Fluent builder / DSL for assembling DeeplinkManager at launch.
// Supports result-builder syntax for clean, readable configuration.

import Foundation

// MARK: - DeeplinkBuilder

/// Fluent configuration builder for `DeeplinkManager`.
///
/// Usage:
/// ```swift
/// let manager = DeeplinkBuilder()
///     .schemes(["myapp", "myapp-debug"])
///     .universalLinkHosts(["app.example.com"])
///     .routes(["product/:productId", "profile/:userId", "home"])
///     .middleware(LoggingMiddleware())
///     .middleware(AuthMiddleware(protectedRoutes: ["profile", "orders"]))
///     .modules([StoreModule(), ProfileModule()])
///     .build()
/// ```

public final class DeeplinkBuilder {

    private var schemes: Set<String> = []
    private var universalLinkHosts: Set<String> = []
    private var templates: [String] = []
    private var middlewareChain: [any DeeplinkMiddleware] = []
    private var modules: [any DeeplinkRegistrable] = []
    private var fallbackHandler: (any DeeplinkHandling)?
    private var configuration = DeeplinkManager.Configuration()
    private var onSuccess: ((DeeplinkContext) -> Void)?
    private var onError: ((DeeplinkContext, Error) -> Void)?
    private var onUnhandled: ((URL) -> Void)?

    public init() {}

    // MARK: - Chainable Configuration

    /// Register custom URL schemes (e.g. "myapp").
    @discardableResult
    public func schemes(_ schemes: Set<String>) -> DeeplinkBuilder {
        self.schemes = schemes
        return self
    }

    /// Register universal link hosts (e.g. "app.example.com").
    @discardableResult
    public func universalLinkHosts(_ hosts: Set<String>) -> DeeplinkBuilder {
        universalLinkHosts = hosts
        return self
    }

    /// Register URL path templates (e.g. "product/:productId").
    @discardableResult
    public func routes(_ templates: [String]) -> DeeplinkBuilder {
        self.templates = templates
        return self
    }

    /// Add a middleware to the pipeline.
    @discardableResult
    public func middleware(_ middleware: any DeeplinkMiddleware) -> DeeplinkBuilder {
        middlewareChain.append(middleware)
        return self
    }

    /// Add multiple middleware at once.
    @discardableResult
    public func middleware(_ middleware: [any DeeplinkMiddleware]) -> DeeplinkBuilder {
        middlewareChain.append(contentsOf: middleware)
        return self
    }

    /// Register feature modules.
    @discardableResult
    public func modules(_ modules: [any DeeplinkRegistrable]) -> DeeplinkBuilder {
        self.modules = modules
        return self
    }

    /// Set a fallback handler for unmatched routes.
    @discardableResult
    public func fallback(_ handler: any DeeplinkHandling) -> DeeplinkBuilder {
        fallbackHandler = handler
        return self
    }

    /// Modify the default configuration.
    @discardableResult
    public func configure(_ block: (inout DeeplinkManager.Configuration) -> Void) -> DeeplinkBuilder {
        block(&configuration)
        return self
    }

    /// Set callbacks.
    @discardableResult
    public func onSuccess(_ handler: @escaping (DeeplinkContext) -> Void) -> DeeplinkBuilder {
        onSuccess = handler
        return self
    }

    @discardableResult
    public func onError(_ handler: @escaping (DeeplinkContext, Error) -> Void) -> DeeplinkBuilder {
        onError = handler
        return self
    }

    @discardableResult
    public func onUnhandled(_ handler: @escaping (URL) -> Void) -> DeeplinkBuilder {
        onUnhandled = handler
        return self
    }

    // MARK: - Build

    /// Assemble and return a configured `DeeplinkManager`.
    @discardableResult
    public func build(into manager: DeeplinkManager = .shared) -> DeeplinkManager {
        // Build schemes set: custom + universal
        var allSchemes = schemes
        allSchemes.insert("https")
        allSchemes.insert("http")

        // Build parser from all templates
        let parser = StandardURLParser(
            schemes: allSchemes,
            templates: templates
        )
        manager.configure(parser: parser)

        // Attach middleware
        manager.setMiddleware(middlewareChain)

        // Register modules
        manager.registerModules(modules)

        // Register fallback
        if let fallback = fallbackHandler {
            manager.registerFallback(handler: fallback)
        }

        // Apply configuration
        manager.configuration = configuration

        // Set callbacks
        manager.onSuccess = onSuccess
        manager.onError = onError
        manager.onUnhandled = onUnhandled

        return manager
    }
}
