// Created by Kanan Abilzada.
import Foundation

final class LockedArray<Element>: @unchecked Sendable {
    private var items: [Element] = []
    private let lock = NSLock()

    func append(_ item: Element) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    var snapshot: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func set(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    var snapshot: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
