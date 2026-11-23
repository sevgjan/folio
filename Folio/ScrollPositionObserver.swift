import AppKit
import SwiftUI

// @Observable, not @State on the caller's side: boundsDidChangeNotification fires continuously
// during a scroll gesture, and a plain @State var read by the caller's own body would force the
// whole view (sidebar, markdown tree, toolbar, everything) to re-render on every single tick.
// Only views that actually read `.progress` — i.e. just StatusBarView — get invalidated this way.
@Observable
final class ScrollProgressTracker {
    var progress: Double = 0
}

// Same isolation reasoning as above, for the outline sidebar's "current section" highlight:
// only OutlineSidebarView should re-render when the visible block changes, not ContentView.
@Observable
final class VisibleBlockTracker {
    var blockID: Int?
}

/// SwiftUI's ScrollView on macOS exposes no scroll-offset API, so this bridges to the
/// underlying NSScrollView and reports reading progress as its bounds change. Place it
/// anywhere inside the scrolling content; it walks up the view hierarchy to find the
/// enclosing NSScrollView.
struct ScrollPositionObserver: NSViewRepresentable {
    var onChange: (Double) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onChange = onChange
        DispatchQueue.main.async { context.coordinator.attach(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    @MainActor final class Coordinator: NSObject {
        var onChange: (Double) -> Void
        private(set) var isObserving = false
        private var scrollView: NSScrollView?

        init(onChange: @escaping (Double) -> Void) {
            self.onChange = onChange
        }

        func attach(to view: NSView) {
            guard !isObserving else { return }
            guard let scrollView = enclosingScrollView(of: view) else { return }
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            isObserving = true
            report()
        }

        @objc private func boundsDidChange(_ note: Notification) {
            report()
        }

        private func report() {
            guard let scrollView, let document = scrollView.documentView else { return }
            let contentHeight = document.frame.height
            let visibleHeight = scrollView.contentView.bounds.height
            guard contentHeight > visibleHeight else {
                onChange(0)
                return
            }
            let offset = scrollView.contentView.bounds.minY
            onChange(min(max(offset / (contentHeight - visibleHeight), 0), 1))
        }

        private func enclosingScrollView(of view: NSView) -> NSScrollView? {
            var current = view.superview
            while let candidate = current {
                if let scrollView = candidate as? NSScrollView { return scrollView }
                current = candidate.superview
            }
            return nil
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}


struct ReadingProgressObserver: ViewModifier {
    let tracker: ScrollProgressTracker

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Double.self) { geometry in
                let length = geometry.contentSize.height + geometry.contentInsets.top +
                    geometry.contentInsets.bottom - geometry.containerSize.height
                guard length > 0 else { return 0 }
                let position = geometry.contentOffset.y + geometry.contentInsets.top
                return min(max(Double(position / length), 0), 1)
            } action: { _, progress in
                tracker.progress = progress
            }
        } else {
            content
        }
    }
}
