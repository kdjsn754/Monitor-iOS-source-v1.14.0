import SwiftUI

/// 全部在线设备。
///
/// 以前是从概览卡片 NavigationLink 推一个二级页出来，为了看一眼 IP 就得离开首页、
/// 还得再返回一次。现在改成弹窗：卡片上点「查看全部」直接浮起来，看完下拉或
/// 点右上角叉就回去，概览的滚动位置和实时曲线都不受影响。
///
/// 版式与「切换连接」「选择配置文件」两个面板完全一致：同一个 `SheetSurface` 底、
/// 同一种「标题 + 小字 + 圆形叉」的表头、同一种浅色圆角行。之前这个弹窗走的是
/// 系统的 `navigationTitle` + 导航栏「完成」，行又是一整块白卡加分隔线，
/// 跟另外两个自绘面板摆在一起像两个 App 的东西。
struct DeviceListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// 正在改名的设备 + 输入框内容。点一行就进这里。
    @State private var renaming: DeviceInfo?
    @State private var showRename = false
    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 8) {
                    if model.devices.isEmpty {
                        emptyState
                    } else {
                        // 用 IP 做标识：每轮采集都会重建 DeviceInfo，id 每次都不一样，
                        // 换成 IP 行才不会每 2 秒被整体重建一次。
                        ForEach(model.devices, id: \.ip) { device in
                            row(device)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(SheetSurface())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    /// 和另外两个面板同一个表头：左边两行字、右边一枚圆形叉。
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("连接设备")
                    .font(.headline)
                Text(headerCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .softTile(.blue, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var headerCaption: String {
        guard !model.devices.isEmpty else { return "DHCP 租约里还没有设备" }
        return "\(model.devices.count) 台在线 · 点一行可改名"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("暂无 DHCP 租约设备")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .softTile(.blue, radius: 14)
    }

    /// 一行一块浅色圆角底，和配置选择器里的行同一套：头像 / 名字 + IP·MAC / 铅笔。
    private func row(_ device: DeviceInfo) -> some View {
        let name = model.displayName(for: device)
        return Button {
            draftName = model.hasAlias(device) ? name : device.name
            renaming = device
            showRename = true
        } label: {
            HStack(spacing: 11) {
                Text(initial(name))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .softTile(.blue, in: Circle())

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

                Spacer(minLength: 4)

                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 26, height: 26)
                    .softTile(.blue, in: Circle())
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .softTile(.blue, radius: 13)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
