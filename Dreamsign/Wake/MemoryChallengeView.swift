import SwiftUI

struct MemoryChallengeView: View {
    let length: Int
    var onActivity: () -> Void
    var onComplete: () -> Void

    private enum Phase { case watching, repeating, solved }

    @State private var game: MemoryGame
    @State private var phase: Phase = .watching
    @State private var lit: Int?
    @State private var flash: Int?
    @State private var mistakes = 0
    @State private var round = 0

    init(length: Int, onActivity: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.length = length
        self.onActivity = onActivity
        self.onComplete = onComplete
        var game = MemoryGame(length: length)
        if Showcase.isActive {
            var random = SeededRandomNumberGenerator(seed: 4)
            game.newPattern(using: &random)
        } else {
            game.newPattern()
        }
        _game = State(initialValue: game)
    }

    var body: some View {
        FoldAwareSplit {
            VStack(spacing: 16) {
                ChallengeHeader(title: "Watch, then repeat", subtitle: subtitle)
                progressDots
                Spacer(minLength: 0)
            }
        } secondary: {
            grid
                .frame(maxHeight: .infinity)
        } stacked: {
            VStack(spacing: 24) {
                ChallengeHeader(title: "Watch, then repeat", subtitle: subtitle)
                progressDots
                Spacer(minLength: 0)
                grid
                Spacer(minLength: 0)
            }
        }
        .task(id: round) { await playPattern() }
        .sensoryFeedback(.error, trigger: mistakes)
        .sensoryFeedback(.success, trigger: phase == .solved)
    }

    private var subtitle: LocalizedStringKey {
        switch phase {
        case .watching: "\(length) lights. Watch closely."
        case .repeating: "Your turn — tap them in order."
        case .solved: "Sharp."
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<game.pattern.count, id: \.self) { index in
                Circle()
                    .fill(index < game.entered.count || phase == .solved ? Palette.mint : Palette.text.opacity(0.15))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.3), value: game.entered.count)
        .accessibilityElement()
        .accessibilityLabel("\(game.entered.count) of \(game.pattern.count)")
    }

    private var grid: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        tile(row * 3 + column)
                    }
                }
            }
        }
        .frame(maxWidth: 360)
        .aspectRatio(1, contentMode: .fit)
        .padding(.bottom, 8)
        .modifier(ShakeEffect(animatableData: CGFloat(mistakes)))
        .animation(.linear(duration: 0.4), value: mistakes)
    }

    private func tile(_ index: Int) -> some View {
        let isLit = lit == index || flash == index
        return Button { tap(index) } label: {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isLit ? AnyShapeStyle(LinearGradient(colors: [Palette.dawn, Palette.iris], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Palette.surfaceRaised))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(isLit ? Color.white.opacity(0.5) : Palette.hairline)
                }
                .shadow(color: isLit ? Palette.dawn.opacity(0.5) : .clear, radius: 16)
                .scaleEffect(isLit ? 1.04 : 1)
                .aspectRatio(1, contentMode: .fit)
                .animation(.easeOut(duration: 0.15), value: isLit)
        }
        .buttonStyle(.plain)
        .disabled(phase != .repeating)
        .accessibilityLabel("Tile \(index + 1)")
    }

    private func playPattern() async {
        phase = .watching
        lit = nil
        try? await Task.sleep(for: .milliseconds(round == 0 ? 900 : 700))
        if Showcase.isActive {
            lit = game.pattern.first
            return
        }
        for tile in game.pattern {
            guard !Task.isCancelled else { return }
            lit = tile
            try? await Task.sleep(for: .milliseconds(520))
            lit = nil
            try? await Task.sleep(for: .milliseconds(220))
        }
        phase = .repeating
    }

    private func tap(_ index: Int) {
        onActivity()
        flash = index
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            if flash == index { flash = nil }
        }
        switch game.tap(index) {
        case .correct:
            break
        case .solved:
            phase = .solved
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                onComplete()
            }
        case .mistake:
            mistakes += 1
            phase = .watching
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                game.newPattern()
                round += 1
            }
        }
    }
}
