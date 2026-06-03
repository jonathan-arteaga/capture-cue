import SwiftUI

struct SectionHeader: View {
  var icon: String? = nil
  let title: String

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let _ = colorScheme
    if let icon {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: FontSize.sm))
          .foregroundStyle(CaptureCueColors.secondaryText)
        Text(title)
          .font(.system(size: FontSize.xs, weight: .semibold))
          .foregroundStyle(CaptureCueColors.primaryText)
      }
    } else {
      Text(title)
        .font(.system(size: FontSize.xxs, weight: .semibold))
        .foregroundStyle(CaptureCueColors.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
  }
}
