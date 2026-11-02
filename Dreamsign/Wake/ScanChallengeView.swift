import SwiftUI
import VisionKit

/// Live barcode / QR scanner (VisionKit). Reports each new payload once.
struct CodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    static var isUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode()],
                                                qualityLevel: .balanced,
                                                recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        guard !scanner.isScanning else { return }
        DispatchQueue.main.async { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty {
                    onCode(payload)
                }
            }
        }
    }
}

/// Camera frame with corner marks; stands in for the camera where there is none.
struct ScannerFrame<Content: View>: View {
    var tint: Color = Palette.dawn
    @ViewBuilder var content: Content

    var body: some View {
        content
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Palette.hairline)
            }
            .overlay {
                CornerMarks()
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .padding(26)
            }
    }
}

private struct CornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.16
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
        }
        return path
    }
}

struct ScanChallengeView: View {
    let code: String
    let label: String
    var onActivity: () -> Void
    var onComplete: () -> Void

    @State private var finished = false
    @State private var wrongCodes = 0
    @State private var fallback = false

    private var canScan: Bool { !code.isEmpty && CodeScanner.isUsable }

    var body: some View {
        if fallback || (!canScan && !Showcase.isActive) {
            VStack(spacing: 0) {
                Label(code.isEmpty ? "No code set up for this alarm — math instead."
                                   : "The camera isn't available — math instead.",
                      systemImage: "camera.metering.unknown")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, 12)
                MathChallengeView(difficulty: .medium, target: 3, onActivity: onActivity, onComplete: onComplete)
            }
        } else {
            FoldAvoiding(tabletop: .top) {
                VStack(spacing: 20) {
                    ChallengeHeader(title: "Go scan your code", subtitle: label.isEmpty ? nil : "It's at: \(label)")
                    ScannerFrame(tint: finished ? Palette.mint : Palette.dawn) {
                        ZStack {
                            Palette.surface
                            if canScan {
                                CodeScanner { scanned in found(scanned) }
                            } else {
                                Image(systemName: "barcode")
                                    .font(.system(size: 80, weight: .ultraLight))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            if finished {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 84))
                                    .foregroundStyle(Palette.mint)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .frame(maxWidth: 420)
                    .aspectRatio(0.9, contentMode: .fit)
                    .modifier(ShakeEffect(animatableData: CGFloat(wrongCodes)))
                    .animation(.linear(duration: 0.4), value: wrongCodes)

                    if wrongCodes > 0, !finished {
                        Text("That's a different code. Find the one you set up.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.ember)
                    }
                    Spacer(minLength: 0)
                    Button("Can't scan it?") { fallback = true }
                        .buttonStyle(.quiet)
                        .opacity(wrongCodes >= 3 ? 1 : 0)
                        .disabled(wrongCodes < 3)
                }
                .readableWidth()
            }
            .sensoryFeedback(.error, trigger: wrongCodes)
            .sensoryFeedback(.success, trigger: finished)
        }
    }

    private func found(_ scanned: String) {
        onActivity()
        guard !finished else { return }
        guard scanned == code else {
            wrongCodes += 1
            return
        }
        withAnimation(.spring(duration: 0.4)) { finished = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            onComplete()
        }
    }
}

/// Registers the code a scan challenge will ask for.
struct ScanSetupView: View {
    @Binding var challenge: Challenge
    @Environment(\.dismiss) private var dismiss
    @State private var scanned: String?
    @State private var label = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let scanned {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Palette.mint)
                        Text("Got it")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Palette.text)
                        Text(scanned)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 30)
                    TextField("Where is it? (e.g. toothpaste, bathroom)", text: $label)
                        .padding(16)
                        .background(Palette.surface, in: .rect(cornerRadius: 18, style: .continuous))
                    Spacer()
                    Button("Use this code") {
                        challenge.scanCode = scanned
                        challenge.scanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .buttonStyle(.big)
                } else if CodeScanner.isUsable {
                    Text("Scan a barcode or QR code on something that stays put — far from your bed.")
                        .font(.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                    ScannerFrame {
                        CodeScanner { code in if scanned == nil { scanned = code } }
                    }
                    .aspectRatio(0.9, contentMode: .fit)
                    Spacer()
                } else {
                    ContentUnavailableView("Camera unavailable",
                                           systemImage: "camera.metering.unknown",
                                           description: Text("Allow camera access for Dreamsign in Settings to register a code."))
                }
            }
            .padding(Metrics.gutter)
            .readableWidth(520)
            .background(NightBackground(stars: false))
            .navigationTitle("Register a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: scanned)
        .onAppear { label = challenge.scanLabel }
    }
}
