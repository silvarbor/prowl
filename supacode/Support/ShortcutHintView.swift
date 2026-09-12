import SwiftUI

struct ShortcutHintView: View {
  let text: String
  let color: Color
  let style: Font.TextStyle

  init(text: String, color: Color, style: Font.TextStyle = .caption2) {
    self.text = text
    self.color = color
    self.style = style
  }

  var body: some View {
    Text(text)
      .interfaceFont(style)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .foregroundStyle(color)
  }
}
