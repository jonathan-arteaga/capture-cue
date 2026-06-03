import SwiftUI

struct DevicePopover: View {
  let onStart: (String) -> Void

  @State private var selectedDeviceId: String?

  private var devices: [ExternalDevice] {
    DeviceDiscovery.shared.availableDevices
  }

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let _ = colorScheme
    VStack(alignment: .leading, spacing: 0) {
      if devices.isEmpty {
        emptyState
      } else {
        deviceList
      }

      Text("Make sure your device is unlocked before recording")
        .font(.system(size: FontSize.xs))
        .foregroundStyle(CaptureCueColors.tertiaryText)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)

      Button {
        guard let id = selectedDeviceId else { return }
        onStart(id)
      } label: {
        Label("Open Device", systemImage: "iphone.and.arrow.right.inward")
      }
      .buttonStyle(PrimaryButtonStyle(size: .medium, fullWidth: true))
      .disabled(selectedDeviceId == nil)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .padding(.vertical, 8)
    .frame(width: 320)
    .popoverContainerStyle()
    .onChange(of: devices) {
      if devices.count == 1 {
        selectedDeviceId = devices.first?.id
      } else if let sel = selectedDeviceId, !devices.contains(where: { $0.id == sel }) {
        selectedDeviceId = nil
      }
    }
    .onAppear {
      DeviceDiscovery.shared.refreshDevices()
      if devices.count == 1 {
        selectedDeviceId = devices.first?.id
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Image(systemName: "iphone")
        .font(.system(size: FontSize.xxl))
        .foregroundStyle(CaptureCueColors.tertiaryText)
      Text("No devices found")
        .font(.system(size: FontSize.xs, weight: .medium))
        .foregroundStyle(CaptureCueColors.primaryText)
      Text("Connect via USB and unlock")
        .font(.system(size: FontSize.xxs))
        .foregroundStyle(CaptureCueColors.tertiaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }

  private var deviceList: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionHeader(title: "Device")

      ForEach(devices) { device in
        DeviceRow(
          device: device,
          isSelected: selectedDeviceId == device.id
        ) {
          selectedDeviceId = device.id
        }
        .padding(.horizontal, 12)
      }
    }
  }
}

private struct DeviceRow: View {
  let device: ExternalDevice
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  private var isIPad: Bool {
    device.modelID.lowercased().contains("ipad")
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: isIPad ? "ipad" : "iphone")
          .font(.system(size: FontSize.xxxl))
          .foregroundStyle(isSelected ? CaptureCueColors.primaryText : CaptureCueColors.secondaryText)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 1) {
          Text(device.name)
            .font(.system(size: FontSize.xs, weight: .medium))
            .foregroundStyle(CaptureCueColors.primaryText)
            .lineLimit(1)

          Text(isIPad ? "iPad" : "iPhone")
            .font(.system(size: FontSize.xs))
            .foregroundStyle(CaptureCueColors.tertiaryText)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: FontSize.xs, weight: .semibold))
            .foregroundStyle(CaptureCueColors.primaryText)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: Radius.md)
          .strokeBorder(
            isSelected ? CaptureCueColors.ring : CaptureCueColors.border,
            lineWidth: isSelected ? 1.5 : 0.5
          )
          .background(
            RoundedRectangle(cornerRadius: Radius.md)
              .fill(
                isSelected ? CaptureCueColors.accent : (isHovered ? CaptureCueColors.hoverBackground : Color.clear)
              )
          )
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PlainCustomButtonStyle())
    .onHover { isHovered = $0 }
  }
}
