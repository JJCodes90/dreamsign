import SwiftData
import SwiftUI

struct JournalChallengeView: View {
    let minimumWords: Int
    let source: EntrySource
    /// Drafts survive the app being killed mid-sentence.
    let draftKey: String
    var onActivity: () -> Void
    var onComplete: (DreamEntry) -> Void

    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var noRecall = false
    @State private var assessment = JournalAssessment(requiredWords: 1)
    @State private var saved = false
    @FocusState private var focused: Bool

    /// Created after the first frame: loading the dictionaries can take a moment.
    @State private var validator: JournalValidator?
    private var draftDefaultsKey: String { "journal-draft.\(draftKey)" }

    private var requirement: JournalRequirement {
        noRecall
            ? JournalRequirement(minimumWords: min(JournalRequirement.noRecall.minimumWords, minimumWords))
            : JournalRequirement(minimumWords: minimumWords)
    }

    /// While typing, drop the subtitle so the short Duo outer display (or landscape) keeps room to write.
    private var compactHeader: Bool { focused && !text.isEmpty }

    var body: some View {
        // Laptop pose: the writing sits on the upper half, the keyboard on the lower.
        FoldAvoiding(tabletop: .top) {
            content
                .readableWidth()
        }
        .sensoryFeedback(.success, trigger: assessment.isAcceptable) { _, acceptable in acceptable }
        .task(id: ValidationKey(text: text, noRecall: noRecall)) {
            guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
            if validator == nil { validator = JournalValidator.system() }
            guard let validator else { return }
            assessment = validator.assess(text, requirement: requirement)
            UserDefaults.standard.set(text, forKey: draftDefaultsKey)
        }
        .onChange(of: text) { onActivity() }
        .onAppear {
            if text.isEmpty, let draft = UserDefaults.standard.string(forKey: draftDefaultsKey) { text = draft }
            if text.isEmpty, Showcase.isActive { text = Showcase.dreamText }
            assessment = JournalAssessment(requiredWords: requirement.minimumWords)
            focused = true
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if noRecall {
                ChallengeHeader(title: "First thoughts?",
                                subtitle: compactHeader ? nil : "Feelings, fragments, whatever's there.")
            } else {
                ChallengeHeader(title: "What did you dream?",
                                subtitle: compactHeader ? nil : "Where were you? Who was there? How did it feel?")
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.title3)
                    .foregroundStyle(Palette.text)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .accessibilityLabel(noRecall ? "First thoughts" : "Dream")
                if text.isEmpty {
                    Text(noRecall ? "I woke up feeling…" : "I was…")
                        .font(.title3)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Palette.ink.opacity(0.5), in: .rect(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline))

            VStack(alignment: .leading, spacing: 8) {
                GoalBar(progress: assessment.progress)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(assessment.realWordCount) of \(requirement.minimumWords) words")
                        .monospacedDigit()
                        .foregroundStyle(assessment.meetsCount ? Palette.mint : Palette.textSecondary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    if let issue = assessment.primaryIssue, !text.isEmpty {
                        Text(issue.message)
                            .foregroundStyle(Palette.ember)
                            .multilineTextAlignment(.trailing)
                            .transition(.opacity)
                    }
                }
                .font(.subheadline)
            }
            .animation(.easeOut(duration: 0.2), value: assessment)

            HStack(spacing: 12) {
                Button(noRecall ? "I remember something" : "Can't remember") {
                    withAnimation(.smooth) { noRecall.toggle() }
                }
                .buttonStyle(.quiet)
                .fixedSize()

                Button("Save", action: save)
                    .buttonStyle(.big(Palette.mint))
                    .disabled(!assessment.isAcceptable || saved)
            }
        }
        .animation(.easeOut(duration: 0.2), value: compactHeader)
    }

    private func save() {
        guard assessment.isAcceptable, !saved else { return }
        saved = true
        let entry = DreamEntry(text: text.trimmingCharacters(in: .whitespacesAndNewlines), isNoRecall: noRecall, source: source)
        context.insert(entry)
        try? context.save()
        UserDefaults.standard.removeObject(forKey: draftDefaultsKey)
        focused = false
        onComplete(entry)
    }

    private struct ValidationKey: Equatable {
        var text: String
        var noRecall: Bool
    }
}
