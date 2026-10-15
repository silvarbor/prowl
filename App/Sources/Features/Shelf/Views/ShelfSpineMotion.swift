import SwiftUI

/// Keep book movement outside the spine's interactive content.
struct ShelfSpineMotion: ViewModifier {
  func body(content: Content) -> some View {
    content
      // Commit selection chrome and footer layout once. Local hover animations
      // can still supply their own transaction inside this boundary.
      .transaction { $0.animation = nil }
      // This must stay outside the transaction override so the parent can
      // animate the whole spine without animating each descendant's geometry.
      .geometryGroup()
  }
}
