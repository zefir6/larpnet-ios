import SwiftUI
import UIKit

/// Downscaled chat images, keyed by `ChatImage.sourceJson` -- bubbles in a long thread scroll
/// in and out of a `LazyVStack`, and re-fetching and re-decoding each time would flicker.
/// `@unchecked Sendable`: `NSCache` is thread-safe (same as `ImageLoader`).
private final class ChatImageCache: @unchecked Sendable {
    static let shared = ChatImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

/// An `m.image` message's bubble: the picture itself (sized from the event's width/height while
/// it loads), tapping opens `ChatImageViewer`.
struct ChatImageView: View {
    let image: ChatImage
    let appContainer: AppContainer

    @State private var loaded: UIImage?
    @State private var failed = false
    @State private var showViewer = false

    private static let maxSide: CGFloat = 240

    var body: some View {
        Group {
            if let loaded {
                Image(uiImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        if failed {
                            Label("Couldn't load image", systemImage: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { if loaded != nil { showViewer = true } }
        .fullScreenCover(isPresented: $showViewer) {
            ChatImageViewer(image: image, preview: loaded, appContainer: appContainer)
        }
        .task(id: image.sourceJson) { await load() }
    }

    /// Bubble size: the event's own aspect ratio when it has one (the apps always send it; the
    /// web client doesn't), else the loaded image's, else a 4:3 placeholder.
    private var size: CGSize {
        let ratio: CGFloat
        if let w = image.width, let h = image.height, w > 0, h > 0 {
            ratio = CGFloat(w) / CGFloat(h)
        } else if let loaded, loaded.size.height > 0 {
            ratio = loaded.size.width / loaded.size.height
        } else {
            ratio = 4 / 3
        }
        return ratio >= 1
            ? CGSize(width: Self.maxSide, height: Self.maxSide / ratio)
            : CGSize(width: Self.maxSide * ratio, height: Self.maxSide)
    }

    private func load() async {
        if let cached = ChatImageCache.shared.image(for: image.sourceJson) {
            loaded = cached
            return
        }
        do {
            let data = try await appContainer.matrixClientStore.chatImage(image)
            guard let full = UIImage(data: data) else { failed = true; return }
            let thumbnail = await full.byPreparingThumbnail(ofSize: CGSize(width: 720, height: 720)) ?? full
            ChatImageCache.shared.store(thumbnail, for: image.sourceJson)
            loaded = thumbnail
        } catch {
            failed = true
        }
    }
}

/// Full-screen, zoomable chat image -- shows the bubble's downscaled copy right away and swaps
/// in the full-resolution one once it's loaded.
struct ChatImageViewer: View {
    let image: ChatImage
    let preview: UIImage?
    let appContainer: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var full: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let shown = full ?? preview {
                ZoomableImageView {
                    Image(uiImage: shown).resizable().aspectRatio(contentMode: .fit)
                }
                // Centred: the ZStack is top-trailing for the close button.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .task {
            if let data = try? await appContainer.matrixClientStore.chatImage(image) {
                full = UIImage(data: data)
            }
        }
    }
}
