import SwiftUI

/// 全部在线设备。
///
/// 以前是从概览卡片 NavigationLink 推一个二级页出来，为了看一眼 IP 就得离开首页、
/// 还得再返回一次。现在改成弹窗：卡片上点「查看全部」直接浮起来，看完下拉或
/// 点「完成」就回去，概览的滚动位置和实时曲线都不受影响。
///
/// 版式统一成「34pt 头像 + 名字 + IP · MAC 两行」：所有行共用一条左边界、
/// 同样 10pt 上下留白，名字长短不会再把右边的内容顶来顶去。
struct DeviceListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// 正在改名的设备 + 输入框内容。点一行就进这里。
    @State private var renaming: DeviceInfo?
    @State private var showRename = false
    @State private var draftName = ""

    /// 头像 34 + 间距 12 + 行内左边距 12 = 58，分隔线从这个位置开始，
    /// 正好和文字的左边对齐。
    private let dividerInset: CGFloat = 58

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if model.devices.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            // 用 IP 做标识：每轮采集都会重建 DeviceInfo，id 每次都不一样，
                            // 换成 IP 行才不会每 2 秒被整体重建一次。
                            ForEach(Array(model.devices.enumerated()), id: \.element.ip) { index, device in
                                if index > 0 {
                                    Divider().opacity(0.6).padding(.leading, dividerInset)
                                }
                                row(device)
                            }
                        }
                        .glassCard(padding: 0, cornerRadius: 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
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
            .alert("重命名设备", isPresented: $showRename, presenting: renaming) { device in
                TextField("设备名称", text: $draftName)
                Button("保存") {
                    model.setDeviceAlias(draftName, for: device)
                }
                Button("恢复原名", role: .destructive) {
                    model.setDeviceAlias("", for: device)
                }
                Button("取消", role: .cancel) {}
            } message: { device in
                Text("原名 \(device.name) · \(device.ip)。改名只存在这台手机上，路由器那边不受影响。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(model.devices.count)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                    Text("台设备")
                        .font(.subheadline.weight(.medium))
                }
                Text("DHCP 租约 · 点一行可改名")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
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
        let name = model.displayName(for: device)
        return Button {
            draftName = model.hasAlias(device) ? name : device.name
            renaming = device
            showRename = true
        } label: {
            HStack(spacing: 12) {
                Text(initial(name))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // IP 和 MAC 拆成两列：IP 给一个固定宽度（13 个等宽字符放得下），
                    // 后面那个「·」和 MAC 因此每行都从同一个 x 起步。
                    // 原来是一整串「IP · MAC」，IP 少一位整行就往左缩一格，
                    // 四行下来中间那个点参差不齐，看着就像没对齐。
                    HStack(spacing: 6) {
                        Text(device.ip)
                            .frame(minWidth: 88, alignment: .leading)
                        Text("·")
                        Text(device.mac.uppercased())
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 26, height: 26)
                    .background(Color.blue.opacity(0.10), in: Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，\(device.ip)，点按重命名")
    }

    private func initial(_ name: String) -> String {
        guard let first = name.first, first.isLetter || first.isNumber else {
            return "?"
        }
        return String(first).uppercased()
    }
}
