import SwiftUI

/// Tappable "N new posts" banner shown above a timeline when polling finds new content while
/// the user is mid-scroll -- direct port of Android's `ui/timeline/NewPostsBanner.kt`. Since
/// the server's streaming endpoints are all unimplemented, timelines poll on an interval and
/// surface new posts this way rather than reflowing the list under the reader; pull-to-refresh
/// merges immediately since that's a direct user action.
struct NewPostsBanner: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\(count) new post\(count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
    }
}
