import SwiftUI

struct PhraseChallengeView: View {
    let length: PhraseLength
    var onActivity: () -> Void
    var onComplete: () -> Void

    @State private var matcher: PhraseMatcher
    @State private var typed = ""
    @State private var finished = false
    @State private var mistakes = 0
    @FocusState private var focused: Bool

    init(length: PhraseLength, onActivity: @escaping () -> Void, onComplete: @escaping () -> Void) {
        self.length = length
        self.onActivity = onActivity
        self.onComplete = onComplete
        let phrase = Showcase.isActive ? length.phrases[0] : (length.phrases.randomElement() ?? length.phrases[0])
        _matcher = State(initialValue: PhraseMatcher(phrase))
        _typed = State(initialValue: Showcase.isActive ? String(phrase.prefix(14)) : "")
    }

    private var matched: String { matcher.matchedPrefix(typed) }
    private var hasMistake: Bool { matcher.hasMistake(typed) }

    /// The phrase with the part typed so far in mint.
    private var phraseText: AttributedString {
        var done = AttributedString(matched)
        done.foregroundColor = Palette.mint
        var rest = AttributedString(String(matcher.target.dropFirst(matched.count)))
        rest.foregroundColor = Palette.text
        return done + rest
    }

    var body: some View {
        FoldAvoiding(tabletop: .top) {
            VStack(alignment: .leading, spacing: 20) {
                ChallengeHeader(title: "Type it out", subtitle: "Exactly as written. Capitals and punctuation don't matter.")

                Text(phraseText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(matcher.target)
                    .textSelection(.disabled)

                GoalBar(progress: matcher.progress(typed), tint: Palette.dawn)

                TextField("Start typing…", text: $typed, axis: .vertical)
                    .font(.title3)
                    .foregroundStyle(hasMistake ? Palette.ember : Palette.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...5)
                    .padding(16)
                    .background(Palette.surface, in: .rect(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(hasMistake ? Palette.ember.opacity(0.6) : Palette.hairline)
                    }
                    .focused($focused)
                    .modifier(ShakeEffect(animatableData: CGFloat(mistakes)))
                    .animation(.linear(duration: 0.4), value: mistakes)
                    .disabled(finished)

                if hasMistake {
                    Text("A letter's off — fix it to keep going.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ember)
                }
                Spacer(minLength: 0)
            }
            .readableWidth()
        }
        .onAppear { if !Showcase.isActive { focused = true } }
        .onChange(of: typed) { old, new in
            onActivity()
            if matcher.hasMistake(new), !matcher.hasMistake(old) { mistakes += 1 }
            guard matcher.isMatch(new), !finished else { return }
            finished = true
            focused = false
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                onComplete()
            }
        }
        .sensoryFeedback(.error, trigger: mistakes)
        .sensoryFeedback(.success, trigger: finished)
    }
}
