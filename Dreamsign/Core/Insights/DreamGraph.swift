import Foundation

/// Dream signs as a map: nodes sized by how often they appear, linked when they show up in
/// the same dream. The layout is a small, deterministic force simulation in a unit square.
struct DreamGraph: Sendable {
    struct Node: Identifiable, Hashable, Sendable {
        var id: String
        var count: Int
        var lucidCount: Int
        var lastSeen: Date
        /// Position in 0…1.
        var x: Double = 0.5
        var y: Double = 0.5
        /// 0…1 relative to the most frequent node.
        var weight: Double = 1
    }

    struct Edge: Hashable, Sendable {
        var a: String
        var b: String
        var count: Int
    }

    struct Dream: Sendable {
        var signs: [String]
        var isLucid: Bool
        var date: Date
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []

    init(dreams: [Dream], limit: Int = 24, iterations: Int = 300) {
        var counts: [String: (count: Int, lucid: Int, last: Date)] = [:]
        var pairs: [String: Int] = [:]
        for dream in dreams {
            let unique = Array(Set(dream.signs)).sorted()
            for sign in unique {
                let current = counts[sign] ?? (0, 0, .distantPast)
                counts[sign] = (current.count + 1, current.lucid + (dream.isLucid ? 1 : 0), max(current.last, dream.date))
            }
            for i in unique.indices {
                for j in unique.indices where j > i {
                    pairs["\(unique[i])\u{1F}\(unique[j])", default: 0] += 1
                }
            }
        }
        let top = counts.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }.prefix(limit)
        let maxCount = Double(top.first?.value.count ?? 1)
        nodes = top.map { Node(id: $0.key, count: $0.value.count, lucidCount: $0.value.lucid, lastSeen: $0.value.last,
                               weight: Double($0.value.count) / maxCount) }
        let kept = Set(nodes.map(\.id))
        edges = pairs.compactMap { key, count in
            let parts = key.split(separator: "\u{1F}").map(String.init)
            guard parts.count == 2, kept.contains(parts[0]), kept.contains(parts[1]) else { return nil }
            return Edge(a: parts[0], b: parts[1], count: count)
        }
        .sorted { ($0.a, $0.b) < ($1.a, $1.b) }
        layout(iterations: iterations)
    }

    func node(_ id: String) -> Node? { nodes.first { $0.id == id } }

    /// Signs that share dreams with `id`, most shared first.
    func neighbors(of id: String) -> [(id: String, count: Int)] {
        edges.compactMap { edge -> (String, Int)? in
            if edge.a == id { return (edge.b, edge.count) }
            if edge.b == id { return (edge.a, edge.count) }
            return nil
        }
        .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
        .map { (id: $0.0, count: $0.1) }
    }

    // MARK: Layout

    private mutating func layout(iterations: Int) {
        guard !nodes.isEmpty else { return }
        let count = nodes.count
        if count == 1 {
            nodes[0].x = 0.5
            nodes[0].y = 0.5
            return
        }
        // Start on a spiral (most frequent in the middle) so the result is stable.
        for index in nodes.indices {
            let angle = Double(index) * 2.399963   // golden angle
            let radius = 0.42 * sqrt(Double(index) / Double(count))
            nodes[index].x = 0.5 + radius * cos(angle)
            nodes[index].y = 0.5 + radius * sin(angle)
        }
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let ideal = 0.9 / sqrt(Double(count))
        var temperature = 0.08
        for _ in 0..<iterations {
            var dx = [Double](repeating: 0, count: count)
            var dy = [Double](repeating: 0, count: count)
            for i in 0..<count {
                for j in (i + 1)..<count {
                    var ddx = nodes[i].x - nodes[j].x
                    var ddy = nodes[i].y - nodes[j].y
                    var distance = sqrt(ddx * ddx + ddy * ddy)
                    if distance < 1e-6 { ddx = 0.01; ddy = 0.01 * Double(i - j); distance = 0.014 }
                    let force = ideal * ideal / distance
                    dx[i] += ddx / distance * force; dy[i] += ddy / distance * force
                    dx[j] -= ddx / distance * force; dy[j] -= ddy / distance * force
                }
            }
            for edge in edges {
                guard let i = index[edge.a], let j = index[edge.b] else { continue }
                let ddx = nodes[i].x - nodes[j].x
                let ddy = nodes[i].y - nodes[j].y
                let distance = max(sqrt(ddx * ddx + ddy * ddy), 1e-6)
                let force = distance * distance / ideal * (1 + log(Double(edge.count)))
                dx[i] -= ddx / distance * force; dy[i] -= ddy / distance * force
                dx[j] += ddx / distance * force; dy[j] += ddy / distance * force
            }
            for i in 0..<count {
                // A pull to the center, stronger for frequent signs, keeps the big stars in
                // the middle and unlinked ones on the map.
                let gravity = 0.8 + 1.6 * nodes[i].weight
                dx[i] += (0.5 - nodes[i].x) * gravity
                dy[i] += (0.5 - nodes[i].y) * gravity
                let length = max(sqrt(dx[i] * dx[i] + dy[i] * dy[i]), 1e-9)
                let step = min(length, temperature)
                nodes[i].x = min(max(nodes[i].x + dx[i] / length * step, 0.12), 0.88)
                nodes[i].y = min(max(nodes[i].y + dy[i] / length * step, 0.12), 0.88)
            }
            temperature = max(temperature * 0.985, 0.002)
        }
    }
}
