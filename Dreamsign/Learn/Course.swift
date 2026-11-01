import Foundation

/// The lucid dreaming course: short, evidence-based lessons. Numbers and claims cite the study
/// they come from; where evidence is thin, the lesson says so.
struct Citation: Hashable, Identifiable, Sendable {
    let text: String
    let url: URL
    var id: String { text }

    init(_ text: String, _ url: String) {
        self.text = text
        self.url = URL(string: url)!
    }
}

enum LessonBlock: Hashable, Sendable {
    case text(String)
    case heading(String)
    case steps([String])
    case tip(String)
    case science(String)
    case caution(String)
    case fact(value: String, label: String)
}

/// Something you can do right after reading.
enum PracticeAction: String, Hashable, Sendable {
    case journal, dreamSigns, realityCheck, mild, ssild, wbtb, nightstand

    var title: String {
        switch self {
        case .journal: String(localized: "Set a wake-up with a dream journal")
        case .dreamSigns: String(localized: "Tag your dream signs")
        case .realityCheck: String(localized: "Do a reality check")
        case .mild: String(localized: "Rehearse MILD now")
        case .ssild: String(localized: "Try an SSILD session")
        case .wbtb: String(localized: "Plan a lucid window")
        case .nightstand: String(localized: "Open Nightstand")
        }
    }

    var symbol: String {
        switch self {
        case .journal: "alarm"
        case .dreamSigns: "tag"
        case .realityCheck: "hand.raised"
        case .mild: "sparkles"
        case .ssild: "eye"
        case .wbtb: "moon.stars"
        case .nightstand: "bed.double"
        }
    }
}

struct Lesson: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let minutes: Int
    let blocks: [LessonBlock]
    var practice: PracticeAction?
    var sources: [Citation] = []
}

struct CourseModule: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let lessons: [Lesson]
}

enum Sources {
    static let saunders2016 = Citation("Saunders, Roe, Smith & Clegg (2016). Lucid dreaming incidence: a quality effects meta-analysis of 50 years of research. Consciousness and Cognition, 43.", "https://nectar.northampton.ac.uk/id/eprint/11136/")
    static let aspy2015 = Citation("Aspy, Delfabbro & Proeve (2015). Is dream recall underestimated by retrospective measures and enhanced by keeping a logbook? Consciousness and Cognition, 33.", "https://pubmed.ncbi.nlm.nih.gov/25725324/")
    static let aspy2017 = Citation("Aspy, Delfabbro, Proeve & Mohr (2017). Reality testing and the mnemonic induction of lucid dreams. Dreaming, 27(3).", "https://www.sciencedaily.com/releases/2017/10/171019100812.htm")
    static let aspy2020 = Citation("Aspy (2020). Findings from the International Lucid Dream Induction Study. Frontiers in Psychology, 11.", "https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2020.01746/full")
    static let erlacher2020 = Citation("Erlacher & Stumbrys (2020). Wake up, work on dreams, back to bed and lucid dream: a sleep laboratory study. Frontiers in Psychology, 11.", "https://pmc.ncbi.nlm.nih.gov/articles/PMC7332853/")
    static let stumbrys2012 = Citation("Stumbrys, Erlacher, Schädlich & Schredl (2012). Induction of lucid dreams: a systematic review of evidence. Consciousness and Cognition, 21(3).", "https://boris.unibe.ch/39251")
    static let laberge1990 = Citation("LaBerge & Rheingold (1990). Exploring the World of Lucid Dreaming. Ballantine.", "https://www.lucidity.com/")
    static let stumbrys2016 = Citation("Stumbrys, Erlacher & Schredl (2016). Effectiveness of motor practice in lucid dreams: a comparison with physical and mental practice. Journal of Sports Sciences, 34(1).", "https://boris.unibe.ch/69281")
    static let macedo2019 = Citation("Macêdo et al. (2019). My dream, my rules: can lucid dreaming treat nightmares? Frontiers in Psychology, 10.", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6902039/")
    static let sharpless2016 = Citation("Sharpless (2016). A clinician's guide to recurrent isolated sleep paralysis. Neuropsychiatric Disease and Treatment, 12.", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4958367/")
    static let konkoly2021 = Citation("Konkoly et al. (2021). Real-time dialogue between experimenters and dreamers during REM sleep. Current Biology, 31.", "https://news.northwestern.edu/stories/2021/02/lucid-dreams-ken-paller")
    static let carr2023 = Citation("Carr et al. (2023). Towards engineering a dream: targeted lucidity reactivation in REM sleep. Psychology of Consciousness.", "https://cronfa.swansea.ac.uk/Record/cronfa53997")
    static let laberge2018 = Citation("LaBerge, LaMarca & Baird (2018). Pre-sleep treatment with galantamine stimulates lucid dreaming. PLoS One, 13(8).", "https://pubmed.ncbi.nlm.nih.gov/30089135/")
    static let hilditch2019 = Citation("Hilditch & McHill (2019). Sleep inertia: current insights. Nature and Science of Sleep, 11.", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6710480/")
}

enum Course {
    static let modules: [CourseModule] = [foundations, awareness, techniques, inTheDream, nightLife, frontier]

    static var lessons: [Lesson] { modules.flatMap(\.lessons) }

    static func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }

    // MARK: - 1. Foundations

    static let foundations = CourseModule(id: "foundations", title: String(localized: "Foundations"), lessons: [
        Lesson(
            id: "what-is-lucid",
            title: String(localized: "What a lucid dream is"),
            subtitle: String(localized: "Knowing you're dreaming, while you dream"),
            symbol: "sparkles",
            minutes: 3,
            blocks: [
                .text(String(localized: "A lucid dream is any dream in which you realize you're dreaming. Sometimes that realization is a flicker before you wake; sometimes it opens into a long, vivid dream you can steer.")),
                .fact(value: "55%", label: String(localized: "of people have had at least one lucid dream")),
                .fact(value: "23%", label: String(localized: "have them once a month or more")),
                .text(String(localized: "Those figures come from a meta-analysis of 50 years of studies. Lucid dreaming is common, and decades of lab work show it's a skill you can train — usually through three habits: remembering dreams, noticing what's odd in them, and setting a clear intention before sleep.")),
                .science(String(localized: "In sleep labs, lucid dreamers signal with pre-agreed eye movements from verified REM sleep. That's how researchers know lucid dreams happen during sleep, not after waking.")),
                .text(String(localized: "This course walks through the methods with the best evidence, in the order that builds on itself. Each lesson ends with something you can try tonight.")),
            ],
            practice: .journal,
            sources: [Sources.saunders2016, Sources.laberge1990]),
        Lesson(
            id: "sleep-101",
            title: String(localized: "How a night of sleep works"),
            subtitle: String(localized: "Why the best dreams come late"),
            symbol: "moon.zzz",
            minutes: 3,
            blocks: [
                .text(String(localized: "Sleep runs in cycles of roughly 90 minutes. Early cycles are dominated by deep, slow-wave sleep. As the night goes on, REM periods — where the most vivid, story-like dreams happen — grow longer.")),
                .text(String(localized: "That's why lucid dreaming techniques focus on the second half of the night, and why a short wake-up after about five hours works so well: you return to sleep right as the longest REM periods begin.")),
                .tip(String(localized: "Waking from deep sleep feels heavy; waking from lighter sleep or REM feels easier. Grogginess is strongest in the first 15–30 minutes after waking — Dreamsign's challenges are designed for exactly that state.")),
                .caution(String(localized: "Lucid dreaming is never worth chronic sleep loss. Keep your total sleep time healthy, and save wake-up techniques for a few nights a week.")),
            ],
            practice: .wbtb,
            sources: [Sources.stumbrys2012, Sources.hilditch2019]),
        Lesson(
            id: "recall",
            title: String(localized: "Remember your dreams"),
            subtitle: String(localized: "The foundation for everything else"),
            symbol: "book.closed",
            minutes: 4,
            blocks: [
                .text(String(localized: "You can't become lucid in a dream you won't remember, and you can't spot patterns in dreams you've forgotten. Recall is the foundation.")),
                .science(String(localized: "Keeping a dream logbook is associated with remembering more dreams than people estimate from memory alone — writing them down appears to train recall itself.")),
                .heading(String(localized: "Each morning")),
                .steps([
                    String(localized: "Before you move, keep your eyes closed and replay what you were just experiencing."),
                    String(localized: "Hold onto any fragment — a face, a place, a feeling — and let it pull the rest back."),
                    String(localized: "Write it down immediately. Dreams fade within minutes, and other tasks wipe them faster."),
                    String(localized: "Nothing came back? Write your first thoughts and feelings. The habit matters more than the content."),
                ]),
                .tip(String(localized: "This is why Dreamsign's journal comes before math in your wake-up challenges: thinking hard about something else is the quickest way to lose a dream.")),
            ],
            practice: .journal,
            sources: [Sources.aspy2015]),
    ])

    // MARK: - 2. Awareness

    static let awareness = CourseModule(id: "awareness", title: String(localized: "Awareness"), lessons: [
        Lesson(
            id: "dream-signs",
            title: String(localized: "Find your dream signs"),
            subtitle: String(localized: "The odd things that keep coming back"),
            symbol: "eye",
            minutes: 4,
            blocks: [
                .text(String(localized: "A dream sign is anything in a dream that would be strange in waking life — and that shows up again and again for you. Stephen LaBerge, who pioneered lucid dreaming research, made them the core of his method.")),
                .heading(String(localized: "Four kinds to look for")),
                .steps([
                    String(localized: "Inner awareness — odd thoughts or feelings, like sudden calm in danger."),
                    String(localized: "Action — impossible things you or others do, like flying or breathing underwater."),
                    String(localized: "Form — things or people that look wrong: changing faces, extra rooms, broken clocks."),
                    String(localized: "Context — being somewhere you shouldn't be, like back at your old school."),
                ]),
                .text(String(localized: "Tag the people, places and themes in your entries. After a couple of weeks, Insights shows which ones recur. Those are your personal cues: the next time one appears, it's a signal to ask, \"Am I dreaming?\"")),
            ],
            practice: .dreamSigns,
            sources: [Sources.laberge1990]),
        Lesson(
            id: "reality-testing",
            title: String(localized: "Reality testing"),
            subtitle: String(localized: "Building the habit of asking"),
            symbol: "hand.raised",
            minutes: 4,
            blocks: [
                .text(String(localized: "A reality test is a quick check of whether you're awake. Done often enough while awake, the habit can carry into dreams — where the check fails, and you realize you're dreaming.")),
                .heading(String(localized: "Checks that tend to fail in dreams")),
                .steps([
                    String(localized: "Read some text, look away, read it again. In dreams it usually changes."),
                    String(localized: "Pinch your nose closed and try to breathe through it."),
                    String(localized: "Look closely at your hands and count your fingers."),
                    String(localized: "Ask how you got here, and look for anything that doesn't fit."),
                ]),
                .science(String(localized: "In the Australian lucid dream induction study, reality testing on its own didn't raise lucid dreaming much. It worked best combined with wake-back-to-bed and MILD.")),
                .tip(String(localized: "Make each check mindful, not mechanical: genuinely consider that you might be dreaming right now. Pair checks with your dream signs — whenever you see one in waking life, check.")),
            ],
            practice: .realityCheck,
            sources: [Sources.aspy2017]),
    ])

    // MARK: - 3. Techniques

    static let techniques = CourseModule(id: "techniques", title: String(localized: "Techniques"), lessons: [
        Lesson(
            id: "mild",
            title: String(localized: "MILD"),
            subtitle: String(localized: "Mnemonic Induction of Lucid Dreams"),
            symbol: "sparkles",
            minutes: 5,
            blocks: [
                .text(String(localized: "MILD trains prospective memory — remembering to do something in the future. The future moment is your next dream; the thing to remember is that you're dreaming.")),
                .heading(String(localized: "How to do it")),
                .steps([
                    String(localized: "Recall: when you wake from a dream, replay it in as much detail as you can."),
                    String(localized: "Intend: as you settle back to sleep, repeat — and mean — \"Next time I'm dreaming, I'll recognize I'm dreaming.\""),
                    String(localized: "Visualize: picture yourself back in the dream you just had. Notice a dream sign, and see yourself realizing it's a dream."),
                    String(localized: "Repeat the intention and visualization until it feels set, then let yourself drift off."),
                ]),
                .fact(value: "46%", label: String(localized: "lucid dream success when people fell asleep within 5 minutes of finishing MILD (Australian study)")),
                .science(String(localized: "In the international follow-up, MILD and SSILD worked about equally well. People with better dream recall, and those who fell asleep within 10 minutes of finishing the technique, succeeded more often.")),
                .tip(String(localized: "Don't force it. A few minutes is enough — the goal is to fall asleep with the intention fresh, not to stay awake practicing.")),
            ],
            practice: .mild,
            sources: [Sources.aspy2017, Sources.aspy2020, Sources.laberge1990]),
        Lesson(
            id: "wbtb",
            title: String(localized: "Wake back to bed"),
            subtitle: String(localized: "A short wake-up at the right moment"),
            symbol: "moon.stars",
            minutes: 4,
            blocks: [
                .text(String(localized: "Wake back to bed (WBTB) means waking up after several hours of sleep, staying awake briefly, then going back to sleep — straight into the long REM periods of early morning, with your mind a little more alert.")),
                .science(String(localized: "In a sleep-lab study, people were woken after 6 hours of sleep, kept awake for 30–60 minutes while practicing MILD, then went back to sleep. Across three experiments, 36–54% reported a lucid dream that morning — and they weren't selected for any lucid dreaming ability. Field studies typically wake people 4½–6 hours after lights out.")),
                .fact(value: "36–54%", label: String(localized: "of lab participants had a lucid dream after WBTB + MILD")),
                .heading(String(localized: "How Dreamsign does it")),
                .steps([
                    String(localized: "A gentle alarm about 5 hours after your bedtime."),
                    String(localized: "A quick journal entry — recall comes first."),
                    String(localized: "A short MILD or SSILD session, with optional voice guidance."),
                    String(localized: "A dim back-to-sleep screen, so you drift off fast."),
                ]),
                .caution(String(localized: "WBTB trims your sleep a little. Two or three nights a week is plenty, and skip it before days you need to be sharp.")),
            ],
            practice: .wbtb,
            sources: [Sources.erlacher2020, Sources.stumbrys2012, Sources.aspy2020]),
        Lesson(
            id: "ssild",
            title: String(localized: "SSILD"),
            subtitle: String(localized: "Senses Initiated Lucid Dream"),
            symbol: "eye",
            minutes: 4,
            blocks: [
                .text(String(localized: "SSILD is a gentle attention exercise for falling back asleep. Instead of an intention, you cycle your attention through your senses, which keeps the mind lightly awake as the body falls asleep.")),
                .heading(String(localized: "One cycle")),
                .steps([
                    String(localized: "Sight: eyes closed, notice the darkness behind your eyelids — colors, patterns, nothing at all."),
                    String(localized: "Sound: shift to what you can hear — room noise, your breath, the hum of silence."),
                    String(localized: "Touch: feel your body — weight, temperature, tingling, any unusual sensations."),
                ]),
                .text(String(localized: "Start with a few quick cycles (a few seconds per sense), then a few slow ones (around 30 seconds each). Then let go and fall asleep normally. Expect nothing in particular during the cycles — that's normal.")),
                .science(String(localized: "In the International Lucid Dream Induction Study, SSILD and MILD were similarly effective, and combining them didn't add anything. Pick the one that feels easier for you.")),
            ],
            practice: .ssild,
            sources: [Sources.aspy2020]),
    ])

    // MARK: - 4. In the dream

    static let inTheDream = CourseModule(id: "in-the-dream", title: String(localized: "In the dream"), lessons: [
        Lesson(
            id: "staying-lucid",
            title: String(localized: "Staying lucid"),
            subtitle: String(localized: "What to do the moment you realize"),
            symbol: "hand.wave",
            minutes: 3,
            blocks: [
                .text(String(localized: "The first lucid dreams often end seconds after they begin — the excitement wakes you up. Expect it, and stay calm.")),
                .heading(String(localized: "Practitioner techniques")),
                .steps([
                    String(localized: "Stay calm and slow down. Take a breath in the dream."),
                    String(localized: "Engage your senses: rub your dream hands together, touch surfaces, look closely at details."),
                    String(localized: "If the dream starts to fade, try spinning around like a child — LaBerge reported this often brings a new, stable scene."),
                    String(localized: "Remind yourself: \"I'm dreaming.\" Lucidity can slip back into a normal dream."),
                ]),
                .caution(String(localized: "These come mostly from practitioners and small informal experiments, not controlled trials. They're harmless to try — just don't expect any one to work every time.")),
            ],
            practice: nil,
            sources: [Sources.laberge1990]),
        Lesson(
            id: "uses",
            title: String(localized: "What lucid dreams are good for"),
            subtitle: String(localized: "Play, practice, and facing fears"),
            symbol: "star",
            minutes: 4,
            blocks: [
                .text(String(localized: "Many people simply explore: flying, visiting places, talking to dream characters. A few uses have been studied.")),
                .science(String(localized: "Practice: in experiments, rehearsing a simple motor task in a lucid dream improved real-world performance, with gains comparable to some forms of waking practice.")),
                .science(String(localized: "Nightmares: case reports and small studies suggest lucidity can reduce nightmare frequency and distress — for example, by facing or changing a recurring threat. The evidence is still limited.")),
                .caution(String(localized: "If nightmares are frequent or linked to trauma, talk to a professional. Imagery rehearsal therapy has much stronger evidence, and lucid dreaming isn't a substitute for care.")),
            ],
            practice: nil,
            sources: [Sources.stumbrys2016, Sources.macedo2019]),
    ])

    // MARK: - 5. Night life

    static let nightLife = CourseModule(id: "night-life", title: String(localized: "Strange but normal"), lessons: [
        Lesson(
            id: "sleep-paralysis",
            title: String(localized: "Sleep paralysis & false awakenings"),
            subtitle: String(localized: "Unsettling, common, and harmless"),
            symbol: "eye.slash",
            minutes: 4,
            blocks: [
                .text(String(localized: "During REM sleep your body is naturally paralyzed so you don't act out dreams. Occasionally you become aware before that paralysis lifts: you're awake, but can't move, sometimes with a sense of presence or vivid imagery.")),
                .fact(value: "~8%", label: String(localized: "of people experience sleep paralysis at least once; far more among students")),
                .steps([
                    String(localized: "Remind yourself what it is: a normal REM state that always passes."),
                    String(localized: "Focus on small movements — wiggle a finger or toe — or on slow breathing."),
                    String(localized: "Some practitioners use it as a doorway: relax instead of fighting it, and let a dream form."),
                ]),
                .text(String(localized: "A false awakening is dreaming that you've woken up. It's common when you're focused on waking or lucid dreaming. Do a reality check every time you wake — sometimes you'll discover you're still dreaming.")),
                .caution(String(localized: "Frequent, distressing sleep paralysis or extreme daytime sleepiness is worth discussing with a doctor.")),
            ],
            practice: .realityCheck,
            sources: [Sources.sharpless2016]),
        Lesson(
            id: "safety",
            title: String(localized: "Good sleep comes first"),
            subtitle: String(localized: "How to practice safely"),
            symbol: "heart",
            minutes: 3,
            blocks: [
                .steps([
                    String(localized: "Protect your total sleep. Use wake-up techniques a few nights a week, not every night."),
                    String(localized: "Keep a regular schedule — it makes REM timing more predictable, too."),
                    String(localized: "If practice makes you anxious or disturbs your sleep, take a break."),
                    String(localized: "If you live with a sleep disorder, or a mental health condition affected by sleep, check with a professional before trying WBTB."),
                ]),
                .science(String(localized: "In the Australian study, people who succeeded with MILD weren't more sleep deprived the next day — practiced sensibly, lucid dreaming doesn't have to cost you rest.")),
            ],
            practice: .nightstand,
            sources: [Sources.aspy2017]),
    ])

    // MARK: - 6. Frontier

    static let frontier = CourseModule(id: "frontier", title: String(localized: "The frontier"), lessons: [
        Lesson(
            id: "frontier",
            title: String(localized: "Where the science is going"),
            subtitle: String(localized: "Talking to dreamers, cueing lucidity"),
            symbol: "atom",
            minutes: 5,
            blocks: [
                .science(String(localized: "Two-way communication: in 2021, four labs showed that lucid dreamers in verified REM sleep could hear questions — even simple math — and answer with eye movements or facial muscles.")),
                .science(String(localized: "Cueing: people trained to associate a sound and light with self-awareness, then cued during REM in a 90-minute nap, reached verified lucid dreams far more often than uncued nappers (50% vs 17%).")),
                .fact(value: "50%", label: String(localized: "of cued nappers had a verified lucid dream, vs 17% without cues")),
                .science(String(localized: "Medication: in a placebo-controlled study of experienced, motivated participants, galantamine taken during a WBTB wake-up raised lucid dream reports from 14% to 42% at the higher dose.")),
                .caution(String(localized: "Don't self-medicate. Galantamine is a prescription drug with side effects and interactions — the study participants were screened and supervised.")),
            ],
            practice: nil,
            sources: [Sources.konkoly2021, Sources.carr2023, Sources.laberge2018]),
    ])
}
