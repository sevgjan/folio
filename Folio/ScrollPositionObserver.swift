import AppKit
import SwiftUI

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

    final class Coordinator: NSObject {
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
