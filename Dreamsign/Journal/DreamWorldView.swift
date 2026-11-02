import SwiftData
import SwiftUI

/// The places, people and themes that keep coming back, as a star map.
struct DreamWorldView: View {
    @Query(sort: \DreamEntry.createdAt, order: .reverse) private var entries: [DreamEntry]
    @Query private var signs: [DreamSign]
    @State private var filter: DreamSignCategory?
    @State private var selection: String?
    @State private var intention = NightPreferences.intentionSign

    private var signsByKey: [String: DreamSign] {
        Dictionary(signs.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var graph: DreamGraph {
        let byKey = signsByKey
        let dreams = entries.filter { !$0.isNoRecall }.map { entry in
            DreamGraph.Dream(signs: entry.signs.map(\.key).filter { key in
                filter == nil || byKey[key]?.category == filter
            }, isLucid: entry.isLucid, date: entry.createdAt)
        }
        return DreamGraph(dreams: dreams)
    }

    var body: some View {
        let graph = graph
        let byKey = signsByKey
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(entries.filter { !$0.isNoRecall }.count) dreams · the places and people that keep coming back")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                filterBar
                if graph.nodes.isEmpty {
                    ContentUnavailableView("Nothing on the map yet",
                                           systemImage: "sparkles",
                                           description: Text("Tag dream signs on your entries and they'll appear here, linked when they share a dream."))
                        .frame(minHeight: 360)
                } else {
                    GeometryReader { proxy in
                        map(graph, byKey: byKey, size: proxy.size)
                    }
                    .aspectRatio(0.85, contentMode: .fit)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    if let selection, let node = graph.node(selection), let sign = byKey[selection] {
                        detail(node, sign: sign, graph: graph, byKey: byKey)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Text("Tap a star to see what it connects to.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 24)
            .readableWidth(640)
        }
        .background(NightBackground())
        .navigationTitle("Your dream world")
        .animation(.smooth(duration: 0.35), value: selection)
        .animation(.smooth(duration: 0.5), value: filter)
        .onAppear {
            if selection == nil { selection = graph.nodes.first?.id }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil, title: String(localized: "All"))
                ForEach(DreamSignCategory.allCases) { category in
                    filterChip(category, title: category.plural)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func filterChip(_ category: DreamSignCategory?, title: String) -> some View {
        let selected = filter == category
        return Button {
            filter = category
            selection = nil
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Palette.ink : Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Palette.iris : Palette.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func map(_ graph: DreamGraph, byKey: [String: DreamSign], size: CGSize) -> some View {
        let positions = Dictionary(uniqueKeysWithValues: graph.nodes.map {
            ($0.id, CGPoint(x: $0.x * size.width, y: $0.y * size.height))
        })
        let highlighted = Set(selection.map { [$0] + graph.neighbors(of: $0).map(\.id) } ?? [])
        return ZStack {
            Canvas { context, _ in
                for edge in graph.edges {
                    guard let a = positions[edge.a], let b = positions[edge.b] else { continue }
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    let active = selection != nil && (edge.a == selection || edge.b == selection)
                    context.stroke(path, with: .color(Palette.iris.opacity(active ? 0.55 : 0.16)),
                                   lineWidth: active ? 2 : 1 + CGFloat(min(edge.count, 4)) * 0.3)
                }
            }
            ForEach(graph.nodes) { node in
                if let sign = byKey[node.id], let point = positions[node.id] {
                    star(node, sign: sign, dimmed: selection != nil && !highlighted.contains(node.id))
                        .position(point)
                }
            }
        }
    }

    private func star(_ node: DreamGraph.Node, sign: DreamSign, dimmed: Bool) -> some View {
        let tint = Self.tint(sign.category)
        let diameter = 34 + 52 * CGFloat(node.weight)
        let selected = selection == node.id
        return Button {
            selection = selected ? nil : node.id
        } label: {
            ZStack {
                Circle()
                    .fill(tint.opacity(selected ? 0.3 : 0.16))
                    .overlay(Circle().strokeBorder(tint.opacity(selected ? 1 : 0.7), lineWidth: selected ? 2.5 : 1.2))
                    .shadow(color: tint.opacity(selected ? 0.6 : 0.25), radius: selected ? 16 : 8)
                if selected {
                    Circle().strokeBorder(tint.opacity(0.3), lineWidth: 1).padding(-8)
                }
                VStack(spacing: 0) {
                    Text(sign.name)
                        .font(.system(size: 10 + 4 * node.weight, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                    if node.weight > 0.6 {
                        Text("\(node.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                .padding(4)
                if node.lucidCount > 0 {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Palette.mint))
                        .offset(x: diameter * 0.36, y: -diameter * 0.36)
                }
            }
            .frame(width: diameter, height: diameter)
            .opacity(dimmed ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(sign.name), \(node.count) dreams"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detail(_ node: DreamGraph.Node, sign: DreamSign, graph: DreamGraph, byKey: [String: DreamSign]) -> some View {
        let neighbors = graph.neighbors(of: node.id).prefix(2).compactMap { byKey[$0.id]?.name }
        let isIntention = intention == sign.key
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(sign.name, systemImage: sign.category.symbol)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Spacer()
                if node.lucidCount > 0 {
                    Chip(text: String(localized: "\(node.lucidCount) lucid"), symbol: "sparkle", tint: Palette.mint)
                }
            }
            Group {
                if neighbors.isEmpty {
                    Text("In \(node.count) dreams. Last seen \(node.lastSeen.formatted(.relative(presentation: .named))).")
                } else {
                    Text("In \(node.count) dreams, often with \(neighbors.formatted(.list(type: .and))). Last seen \(node.lastSeen.formatted(.relative(presentation: .named))).")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                intention = sign.key
                NightPreferences.intentionSign = sign.key
            } label: {
                Label(isIntention ? "Tonight's sign" : "Make it tonight's sign",
                      systemImage: isIntention ? "checkmark" : "moon.stars")
            }
            .buttonStyle(.big(Palette.iris))
            .disabled(isIntention)
        }
        .card(tint: Self.tint(sign.category))
    }

    static func tint(_ category: DreamSignCategory) -> Color {
        switch category {
        case .place: Palette.iris
        case .person: Palette.dawn
        case .theme: Palette.mint
        }
    }
}
