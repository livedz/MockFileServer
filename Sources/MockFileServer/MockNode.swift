//
//  MockNode.swift
//  MockFileServer
//
//  Created by MOKSHA on 21/05/26.
//
import Foundation

// MARK: - Operation

/// Represents one GraphQL/REST operation and its current file mapping
struct MockOperation: Hashable {
    var name: String
    var fileMap: [String: Any]

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: MockOperation, rhs: MockOperation) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Node

/// Enables sequential responses: first call returns node 1,
/// second call to same operation returns node 2, and so on.
///
/// Example use case: Login called twice in one test —
/// first call fails (401), retry succeeds (200).
final class MockNode<T: Hashable> {
    var value: T
    var next: MockNode<T>?
    var isCalled: Bool = false

    init(value: T) {
        self.value = value
    }

    /// Walk the linked list to find the next uncalled node.
    /// If all nodes have been called, replay the last one.
    func nextUncalled() -> MockNode<T> {
        if !isCalled { return self }
        guard let next else { return self } // replay last if exhausted
        return next.nextUncalled()
    }
}
