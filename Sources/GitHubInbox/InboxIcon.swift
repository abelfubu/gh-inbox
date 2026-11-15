import AppKit
import SwiftUI

struct InboxIcon: View {
    let name: String
    var size: CGFloat = 12
    var fallback = "circle"

    init(_ name: String, size: CGFloat = 12, fallback: String = "circle") {
        self.name = name
        self.size = size
        self.fallback = fallback
    }

    var body: some View {
        if name == "pr" || name == "pr-draft" {
            PullRequestIconShape()
                .stroke(style: StrokeStyle(lineWidth: max(1, size / 12), lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        } else if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "icons"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size))
                .frame(width: size, height: size)
        }
    }
}

private struct PullRequestIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        func circle(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: rect.minX + (x - 3) * scale, y: rect.minY + (y - 3) * scale,
                   width: 6 * scale, height: 6 * scale)
        }

        var path = Path()
        path.addEllipse(in: circle(6, 6))
        path.addEllipse(in: circle(6, 18))
        path.addEllipse(in: circle(18, 18))
        path.move(to: point(6, 9))
        path.addLine(to: point(6, 15))
        path.move(to: point(9, 6))
        path.addLine(to: point(11.25, 6))
        path.addCurve(to: point(18, 12.75), control1: point(15, 6), control2: point(18, 9))
        path.addLine(to: point(18, 15))
        return path
    }
}

struct SpinningInboxIcon: View {
    let name: String
    var size: CGFloat = 12
    var fallback = "circle"

    init(_ name: String, size: CGFloat = 12, fallback: String = "circle") {
        self.name = name
        self.size = size
        self.fallback = fallback
    }

    var body: some View {
        // This is an activity indicator, not decorative motion: keep it visible
        // even when macOS Reduce Motion disables optional animations.
        TimelineView(.animation) { timeline in
            let period = 1.0
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let angle = elapsed.truncatingRemainder(dividingBy: period) / period * 360
            InboxIcon(name, size: size, fallback: fallback)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
    }
}
