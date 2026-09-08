import SwiftUI

/// Square pinch-zoom/pan crop UI shown after picking a new avatar and before uploading it. The
/// circular stroke is a visual guide only -- the *exported* image is the full square, matching
/// how Twitter/Mastodon-style avatars are conventionally stored (and later clipped to a circle
/// by every client, this app included). A literal circular-alpha export wouldn't survive a JPEG
/// re-encode anyway.
struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private static let cropSize: CGFloat = 300
    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 4

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                cropArea
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(Self.maxScale, max(Self.minScale, lastScale * value))
                                }
                                .onEnded { _ in lastScale = scale },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                Spacer(minLength: 0)
                Text("Pinch to zoom, drag to reposition")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        if let cropped = renderCroppedImage() {
                            onCrop(cropped)
                        }
                    }
                }
            }
        }
    }

    private var cropArea: some View {
        ZStack {
            croppedContent
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: Self.cropSize, height: Self.cropSize)
                .allowsHitTesting(false)
        }
        .frame(width: Self.cropSize, height: Self.cropSize)
        .contentShape(Rectangle())
    }

    /// Shared between the live interactive preview and the export render, so what the user sees
    /// is exactly what gets uploaded (minus the circular guide, which is drawn separately in
    /// `cropArea` and never included in `renderCroppedImage()`'s content).
    private var croppedContent: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: Self.cropSize, height: Self.cropSize)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: Self.cropSize, height: Self.cropSize)
            .clipped()
    }

    /// `ImageRenderer` (iOS 16+) renders exactly the displayed square content to a `UIImage` at
    /// a fixed higher scale -- no manual geometry/pixel math needed to translate the on-screen
    /// gesture state (scale/offset, in points) into crop coordinates, since it's the same view
    /// tree that's already being displayed.
    private func renderCroppedImage() -> UIImage? {
        let renderer = ImageRenderer(content: croppedContent)
        renderer.scale = 3
        return renderer.uiImage
    }
}
