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
    @Query private var signs: [DreamSign]
    @State private var dictation = DreamDictation()
    @State private var text = ""
    @State private var noRecall = false
    @State private var assessment = JournalAssessment(requiredWords: 1)
    @State private var saved = false
    @FocusState private var focused: Bool
    /// Two-page morning (iPhone Duo open): choices made on the right-hand page.
    @State private var pageChoices = MorningChoices()

    /// Created after the first frame: loading the dictionaries can take a moment.
    @State private var validator: JournalValidator?
    private var draftDefaultsKey: String { "journal-draft.\(draftKey)" }

    private var requirement: JournalRequirement {
        noRecall
            ? JournalRequirement(minimumWords: min(JournalRequirement.noRecall.minimumWords, minimumWords))
            : JournalRequirement(minimumWords: minimumWords)
    }

    /// While typing, drop the subtitle so the short Duo outer display (or landscape) keeps room to write.
    private var compactHeader: Bool { (focused || dictation.isActive) && !text.isEmpty }

    private var signNames: [String] { signs.map(\.name) }

    var body: some View {
        GeometryReader { proxy in
            let fold = FoldGeometry.activeFold(in: proxy)
            let laptop = fold.map { $0.width > $0.height } ?? false
            if !laptop, !noRecall, FoldGeometry.isWide(proxy.size, minimumSideWidth: 340) {
                // Open like a book: write or speak on the left; the right page fills in as you go.
                ArrangementView {
                    content
                } secondary: {
                    MorningSidePage(text: text, signs: signs, source: source, choices: $pageChoices,
                                    canSave: assessment.isAcceptable && !saved) {
                        dictation.stop()
                        save()
                    }
                }
                .arrangementViewStyle(.split)
                .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                // Laptop pose: the writing sits on the upper half, the keyboard on the lower.
                FoldAvoiding(tabletop: .top) {
                    content
                        .readableWidth()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
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
            if Showcase.screen == "wake-voice" { Task { await startDictation() } }
        }
        .onDisappear { dictation.stop() }
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

            if dictation.isActive {
                voicePanel
            } else {
                editor
            }

            if case .unavailable(let message) = dictation.status {
                Label(message, systemImage: "mic.slash")
                    .font(.footnote)
                    .foregroundStyle(Palette.ember)
            }

            progress

            controls
        }
        .animation(.easeOut(duration: 0.2), value: compactHeader)
        .animation(.smooth(duration: 0.3), value: dictation.isActive)
    }

    private var editor: some View {
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
    }

    /// Speaking: the transcript fills in live, with known dream signs highlighted.
    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if text.isEmpty {
                            Text(dictation.isListening ? "Listening… tell it before it fades." : "Paused")
                                .font(.title3)
                                .foregroundStyle(Palette.textTertiary)
                        } else {
                            HighlightedTranscript(text: text, signs: signNames)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: text) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
            .background(Palette.ink.opacity(0.5), in: .rect(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.iris.opacity(0.35)))

            let heard = HighlightedTranscript.mentioned(signNames, in: text)
            if !heard.isEmpty {
                HStack(spacing: 6) {
                    Text("HEARD")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.textTertiary)
                    ForEach(heard.prefix(4), id: \.self) { Chip(text: $0) }
                }
            }
            DictationWaveform(levels: dictation.levels, tint: dictation.isListening ? Palette.iris : Palette.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private var progress: some View {
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
    }

    @ViewBuilder
    private var controls: some View {
        if dictation.isActive {
            HStack(spacing: 12) {
                Button {
                    dictation.stop()
                    focused = true
                } label: {
                    Text("Aa").font(.title3.weight(.bold))
                }
                .buttonStyle(.quiet)
                .accessibilityLabel("Type instead")

                Button {
                    if dictation.isListening { dictation.pause() } else { dictation.resume() }
                } label: {
                    Image(systemName: dictation.isListening ? "pause.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.ink)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Palette.dawn))
                        .shadow(color: Palette.dawn.opacity(0.4), radius: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictation.isListening ? "Pause" : "Keep talking")

                Button("Save") {
                    dictation.stop()
                    save()
                }
                .buttonStyle(.big(Palette.mint))
                .disabled(!assessment.isAcceptable || saved)
            }
        } else {
            HStack(spacing: 12) {
                Button(noRecall ? "I remember something" : "Can't remember") {
                    withAnimation(.smooth) { noRecall.toggle() }
                }
                .buttonStyle(.quiet)
                .fixedSize()

                if DreamDictation.isSupported || Showcase.isActive {
                    Button { Task { await startDictation() } } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.iris)
                            .frame(width: 50, height: 50)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speak your dream")
                }

                Button("Save", action: save)
                    .buttonStyle(.big(Palette.mint))
                    .disabled(!assessment.isAcceptable || saved)
            }
        }
    }

    private func startDictation() async {
        focused = false
        dictation.onText = { heard in
            text = heard
            onActivity()
        }
        await dictation.start(appendingTo: text)
    }

    private func save() {
        guard assessment.isAcceptable, !saved else { return }
        saved = true
        let entry = DreamEntry(text: text.trimmingCharacters(in: .whitespacesAndNewlines), isNoRecall: noRecall, source: source)
        context.insert(entry)
        if !noRecall { pageChoices.apply(to: entry, text: text, signs: signs, context: context) }
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
