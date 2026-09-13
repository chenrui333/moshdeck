import MoshDeckCore
import SwiftUI

struct SessionSwipePreview {
    let source: String
    let target: TmuxSessionSummary?
    let next: Bool
    var progress: Double
}

struct SessionSwipePreviewView: View {
    let preview: SessionSwipePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                preview.next ? "Next session" : "Previous session",
                systemImage: preview.next ? "arrow.left" : "arrow.right"
            )
            .font(.caption)
            Text(preview.target?.name ?? "No more sessions").font(.headline).lineLimit(2)
            if preview.target != nil {
                ProgressView(value: preview.progress)
                Text(preview.progress >= 1 ? "Release to switch" : "Keep dragging to switch")
                    .font(.caption)
            }
        }
        .padding(12).frame(width: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(12).allowsHitTesting(false)
        .accessibilityIdentifier("session.swipe.preview")
    }
}
