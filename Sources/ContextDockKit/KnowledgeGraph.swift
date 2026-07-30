import Foundation

/// In-memory knowledge graph with undo support. Persisted by LocalStore.
/// Nodes are never auto-deleted; archive instead. Merge/unlink are undoable.
public struct KnowledgeGraph: Codable, Sendable {
    public private(set) var nodes: [StableID: KnowledgeNode]
    public private(set) var edges: [KnowledgeEdge]
    private var undoStack: [Snapshot]

    private struct Snapshot: Codable, Sendable {
        var nodes: [StableID: KnowledgeNode]
        var edges: [KnowledgeEdge]
    }

    public init() {
        nodes = [:]
        edges = []
        undoStack = []
    }

    private mutating func checkpoint() {
        undoStack.append(Snapshot(nodes: nodes, edges: edges))
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    public mutating func upsertNode(_ node: KnowledgeNode) {
        checkpoint()
        var node = node
        if let existing = nodes[node.id] {
            node.createdAt = existing.createdAt
            node.updatedAt = Date()
        }
        nodes[node.id] = node
    }

    public mutating func addEdge(_ edge: KnowledgeEdge) {
        guard nodes[edge.sourceID] != nil, nodes[edge.targetID] != nil else { return }
        guard !edges.contains(where: {
            $0.sourceID == edge.sourceID && $0.targetID == edge.targetID && $0.type == edge.type
        }) else { return }
        checkpoint()
        edges.append(edge)
    }

    public mutating func archiveNode(id: StableID) {
        guard var node = nodes[id] else { return }
        checkpoint()
        node.archived = true
        node.updatedAt = Date()
        nodes[id] = node
    }

    public mutating func unlink(sourceID: StableID, targetID: StableID, type: EdgeType) {
        checkpoint()
        edges.removeAll { $0.sourceID == sourceID && $0.targetID == targetID && $0.type == type }
    }

    /// Merge `duplicate` into `canonical`: edges re-pointed, duplicate archived.
    public mutating func merge(duplicate: StableID, into canonical: StableID) {
        guard nodes[duplicate] != nil, nodes[canonical] != nil else { return }
        checkpoint()
        edges = edges.map { edge in
            var edge = edge
            if edge.sourceID == duplicate { edge.sourceID = canonical }
            if edge.targetID == duplicate { edge.targetID = canonical }
            return edge
        }
        edges.removeAll { $0.sourceID == $0.targetID }
        var dup = nodes[duplicate]!
        dup.archived = true
        nodes[duplicate] = dup
    }

    public mutating func undo() -> Bool {
        guard let snapshot = undoStack.popLast() else { return false }
        nodes = snapshot.nodes
        edges = snapshot.edges
        return true
    }

    public func neighbours(of id: StableID) -> [KnowledgeNode] {
        var ids = Set<StableID>()
        for edge in edges {
            if edge.sourceID == id { ids.insert(edge.targetID) }
            if edge.targetID == id { ids.insert(edge.sourceID) }
        }
        return ids.compactMap { nodes[$0] }
    }

    public func nodes(ofType type: NodeType) -> [KnowledgeNode] {
        nodes.values.filter { $0.type == type && !$0.archived }.sorted { $0.title < $1.title }
    }
}
