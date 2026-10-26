import SwiftUI

/// Presented via `.fullScreenCover(item:)` when a post's media thumbnail is tapped -- the
/// "enlarge the image" behavior that was previously missing entirely (tapping a thumbnail just
/// opened the post, since the thumbnail had no tap handler of its own and the tap fell through
/// to the card-wide "open thread" gesture).
struct MediaGalleryContext: Identifiable {
    let attachments: [MediaAttachment]
    let initialIndex: Int
    var id: String { attachments.map(\.id).joined(separator: "-") }
}

struct MediaGalleryView: View {
    let context: MediaGalleryContext
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(context: MediaGalleryContext) {
        self.context = context
        _currentIndex = State(initialValue: context.initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(context.attachments.enumerated()), id: \.offset) { index, media in
                    ZoomableImageView {
                        RemoteImage(url: URL(string: media.url), contentMode: .fit)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: context.attachments.count > 1 ? .always : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .statusBarHidden()
    }
}

/// Pinch-to-zoom + double-tap-to-toggle-zoom, matching the standard iOS photo-viewer gesture
/// set. Callers pass a `.fit` image rather than the `.fill` every other call site uses, since
/// this is a "show the whole image" context, not a thumbnail crop. Also used by chat images
/// (`ChatImageViewer`), whose bytes come from the Matrix SDK rather than a URL.
struct ZoomableImageView<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, min(lastScale * value, 5))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 {
                            resetZoom()
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if scale > 1 {
                        resetZoom()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
