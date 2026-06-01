import SwiftUI

struct Dropdown<Item: Identifiable & Equatable, MenuContent: View>: View {
  let selectedLabel: String
  @Binding var selection: Item
  @ViewBuilder var menuContent: () -> MenuContent

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let _ = colorScheme
    Menu {
      menuContent()
    } label: {
      HStack {
        Text(selectedLabel)
          .font(.system(size: ButtonSize.small.fontSize, weight: ButtonSize.small.fontWeight))
          .foregroundStyle(CaptureCueColors.primaryText)
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: FontSize.xs, weight: .semibold))
          .foregroundStyle(CaptureCueColors.secondaryText)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity)
      .frame(height: ButtonSize.small.height)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: ButtonSize.small.cornerRadius)
          .strokeBorder(CaptureCueColors.border, lineWidth: 1)
      )
    }
    .buttonStyle(PlainCustomButtonStyle())
  }
}
