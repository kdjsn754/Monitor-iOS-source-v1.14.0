import SwiftUI

/// 全部在线设备。
///
/// 以前是从概览卡片 NavigationLink 推一个二级页出来，为了看一眼 IP 就得离开首页、
/// 还得再返回一次。现在改成弹窗：卡片上点「查看全部设备」直接浮起来，看完下拉或
/// 点「完成」就回去，概览的滚动位置和实时曲线都不受影响。
struct DeviceListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    summary
                    if model.devices.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            // 用 IP 做标识：每轮采集都会重建 DeviceInfo，id 每次都不一样，
                            // 换成 IP 行才不会每 2 秒被整体重建一次。
                            ForEach(Array(model.devices.enumerated()), id: \.element.ip) { index, device in
                                if index > 0 {
                                    Divider().padding(.leading, 52)
                                }
                                row(device)
                            }
                        }
                        .glassCard(padding: 4, cornerRadius: 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.clear)
            .navigationTitle("连接设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.devices.count) 台设备")
                    .font(.headline)
                Text("来自路由器 DHCP 租约，不含静态 IP 设备")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("暂无 DHCP 租约设备")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .glassCard(padding: 0, cornerRadius: 18)
    }

    private func row(_ device: DeviceInfo) -> some View {
        HStack(spacing: 12) {
            Text(initial(device))
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(device.ip)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(device.mac.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
    }

    private func initial(_ device: DeviceInfo) -> String {
        guard let first = device.name.first, first.isLetter || first.isNumber else {
            return "?"
        }
        return String(first).uppercased()
    }
}
