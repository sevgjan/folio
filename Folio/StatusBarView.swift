import SwiftUI

struct StatusBarView: View {
    let wordCount: Int
    let characterCount: Int
    let progress: Double

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
