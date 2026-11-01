import SwiftUI

struct MathChallengeView: View {
    let difficulty: MathDifficulty
    let target: Int
    var onActivity: () -> Void
    var onComplete: () -> Void

    @State private var generator: MathProblemGenerator<SystemRandomNumberGenerator>
    @State private var problem: MathProblem
    @State private var input = ""
    @State private var streak = 0
    @State private var wrong = 0
    @State private var right = 0
    @State private var locked = false

    init(difficulty: MathDifficulty, target: Int, onActivity: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.difficulty = difficulty
        self.target = target
        self.onActivity = onActivity
        self.onComplete = onComplete
        var generator = MathProblemGenerator()
        _problem = State(initialValue: generator.next(difficulty))
        _generator = State(initialValue: generator)
    }

    var body: some View {
        FoldAwareSplit {
            problemPanel
        } secondary: {
            keypad
                .frame(maxHeight: .infinity)
        } stacked: {
            VStack(spacing: 0) {
                problemPanel
                keypad
            }
        }
        .sensoryFeedback(.error, trigger: wrong)
        .sensoryFeedback(.success, trigger: right)
        .sensoryFeedback(.selection, trigger: input)
    }

    private var problemPanel: some View {
        VStack(spacing: 0) {
            ChallengeHeader(title: target == 1 ? "Solve this" : "Solve \(target) in a row",
                            subtitle: "A wrong answer starts over.")
            HStack(spacing: 8) {
                ForEach(0..<target, id: \.self) { index in
                    Circle()
                        .fill(index < streak ? Palette.mint : Palette.text.opacity(0.15))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .animation(.spring(duration: 0.3), value: streak)
            .accessibilityElement()
            .accessibilityLabel("\(streak) of \(target) correct")

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text(problem.text)
                    .font(.clock(58, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                    .accessibilityLabel(problem.text.replacingOccurrences(of: "×", with: "times").replacingOccurrences(of: "−", with: "minus"))
                Text(input.isEmpty ? "?" : input)
                    .font(.clock(54, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(input.isEmpty ? Palette.textTertiary : Palette.dawn)
                    .frame(height: 66)
                    .modifier(ShakeEffect(animatableData: CGFloat(wrong)))
                    .animation(.linear(duration: 0.4), value: wrong)
            }

            Spacer(minLength: 12)
        }
    }

    private var keypad: some View {
        Keypad(onDigit: enter, onDelete: { if !input.isEmpty { input.removeLast() } })
            .disabled(locked)
            .frame(maxWidth: 440)
            .padding(.bottom, 4)
    }

    private func enter(_ digit: Int) {
        onActivity()
        let answer = String(problem.answer)
        guard input.count < answer.count else { return }
        input.append(String(digit))
        guard input.count == answer.count else { return }
        check(input == answer)
    }

    private func check(_ correct: Bool) {
        locked = true
        if correct {
            right += 1
            streak += 1
        } else {
            wrong += 1
            streak = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(correct ? 250 : 450))
            if streak >= target {
                onComplete()
                return
            }
            input = ""
            withAnimation(.easeInOut(duration: 0.2)) { problem = generator.next(difficulty) }
            locked = false
        }
    }
}

/// Big, glassy number pad. Keys are 72 pt tall when there's room, never under 54 pt.
struct Keypad: View {
    var onDigit: (Int) -> Void
    var onDelete: () -> Void

    private let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digit in
                        key(Text("\(digit)")) { onDigit(digit) }
                    }
                }
            }
            GridRow {
                Color.clear.frame(minHeight: 54, maxHeight: 72)
                key(Text("0")) { onDigit(0) }
                key(Image(systemName: "delete.left")) { onDelete() }
                    .accessibilityLabel("Delete")
            }
        }
    }

    private func key(_ label: some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(.clock(32, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 72)
                .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }
}
