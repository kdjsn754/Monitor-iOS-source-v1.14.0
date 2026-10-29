import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.devices.isEmpty {
                Text("暂无 DHCP 租约设备")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                    Text(device.ip)
                        .font(.caption.monospacedDigit())
                    Text(device.mac)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .background(Color.clear)
        .navigationTitle("连接设备")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
