import SwiftUI

/// Layout decisions for iPhone Duo (and every other size): stack when tall, split when wide,
/// and when the device is partially folded, keep each part on its own side of the fold.
///
/// The fold is a *division* reserved region (iOS 27.1+). Earlier systems never report one, so
/// everything here degrades to plain size-based layout.
enum FoldGeometry {
    /// The active fold within the proxy's bounds. Its frame already includes the system's
    /// recommended margins.
    static func activeFold(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        guard let region = proxy.reservedRegions(kind: .division).first(where: \.isActive) else { return nil }
        let fold = region.frame.intersection(CGRect(origin: .zero, size: proxy.size))
        guard !fold.isNull, fold.width > 0 || fold.height > 0 else { return nil }
        return fold
    }

    /// Wide enough to put two panes side by side without either feeling cramped.
    static func isWide(_ size: CGSize, minimumSideWidth: CGFloat) -> Bool {
        size.width > size.height * 1.1 && size.width >= minimumSideWidth * 2
    }

    /// The one region that content should move to when it can't sit in the fold.
    /// Book pose → the trailing side (where it continues when the device closes).
    /// Laptop pose → the half you choose: top for things to look at, bottom for things to tap.
    static func region(for proxy: GeometryProxy, tabletop: VerticalEdge) -> CGRect? {
        guard let fold = activeFold(in: proxy) else { return nil }
        let bounds = CGRect(origin: .zero, size: proxy.size)
        if fold.height >= fold.width {
            return CGRect(x: fold.maxX, y: 0, width: max(bounds.maxX - fold.maxX, 0), height: bounds.height)
        }
        return tabletop == .top
            ? CGRect(x: 0, y: 0, width: bounds.width, height: max(fold.minY, 0))
            : CGRect(x: 0, y: fold.maxY, width: bounds.width, height: max(bounds.maxY - fold.maxY, 0))
    }
}

/// A two-part screen: `primary` (read at a glance) and `secondary` (usually what you tap).
///
/// - Tall and unfolded (outer display, regular iPhones): `stacked`, sized naturally.
/// - Wide (inner display open, landscape): side by side.
/// - Partially folded: Apple's `ArrangementView` puts each part on its own side of the fold —
///   left/right like a book, or top/bottom like a laptop.
struct FoldAwareSplit<Primary: View, Secondary: View, Stacked: View>: View {
    var minimumSideWidth: CGFloat
    private let primary: Primary
    private let secondary: Secondary
    private let stacked: Stacked

    init(minimumSideWidth: CGFloat = 300,
         @ViewBuilder primary: () -> Primary,
         @ViewBuilder secondary: () -> Secondary,
         @ViewBuilder stacked: () -> Stacked) {
        self.minimumSideWidth = minimumSideWidth
        self.primary = primary()
        self.secondary = secondary()
        self.stacked = stacked()
    }

    var body: some View {
        GeometryReader { proxy in
            let folded = FoldGeometry.activeFold(in: proxy) != nil
            if folded || FoldGeometry.isWide(proxy.size, minimumSideWidth: minimumSideWidth) {
                split
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                stacked
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    @ViewBuilder
    private var split: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                primary
            } secondary: {
                secondary
            }
            .arrangementViewStyle(.split)
        } else {
            HStack(spacing: 0) {
                primary.frame(maxWidth: .infinity, maxHeight: .infinity)
                secondary.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

extension FoldAwareSplit where Stacked == FoldAwareStack<Primary, Secondary> {
    /// Stacks `primary` above `secondary` when tall.
    init(minimumSideWidth: CGFloat = 300, spacing: CGFloat = 16,
         @ViewBuilder primary: () -> Primary,
         @ViewBuilder secondary: () -> Secondary) {
        let top = primary()
        let bottom = secondary()
        self.init(minimumSideWidth: minimumSideWidth,
                  primary: { top }, secondary: { bottom },
                  stacked: { FoldAwareStack(top: top, bottom: bottom, spacing: spacing) })
    }
}

struct FoldAwareStack<Top: View, Bottom: View>: View {
    let top: Top
    let bottom: Bottom
    var spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            top
            bottom
        }
    }
}

/// Keeps a single block of content out of the fold (Apple's "displacement" pattern).
/// Unfolded, it fills the space as usual.
struct FoldAvoiding<Content: View>: View {
    var tabletop: VerticalEdge
    private let content: Content

    init(tabletop: VerticalEdge = .bottom, @ViewBuilder content: () -> Content) {
        self.tabletop = tabletop
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            if let region = FoldGeometry.region(for: proxy, tabletop: tabletop) {
                content
                    .frame(width: region.width, height: region.height)
                    .position(x: region.midX, y: region.midY)
            } else {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

extension View {
    /// Caps line length on wide displays so text and controls never stretch edge to edge.
    func readableWidth(_ maxWidth: CGFloat = 620) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}
