import SwiftUI

struct StatusBarView: View {
    let wordCount: Int
    let characterCount: Int
    let isPreviewing: Bool
    let scrollTracker: ScrollProgressTracker
    let editProgress: Double

    // Reading scrollTracker.progress here, rather than the caller resolving it into a plain
    // Double, keeps the dependency local to this view — see ScrollProgressTracker's comment.
    private var progress: Double {
        isPreviewing ? scrollTracker.progress : editProgress
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(wordCount) words")
            Text("\(characterCount) characters")
            Spacer()
            Text("\(Int((progress * 100).rounded()))%")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}
