import SwiftUI

/// 全部在线设备。
///
/// 以前是从概览卡片 NavigationLink 推一个二级页出来，为了看一眼 IP 就得离开首页、
/// 还得再返回一次。现在改成底部 sheet 浮起：卡片上点「查看全部」从底部弹出，
/// 拖拽条上下拉伸到半屏/全屏，概览的滚动位置和实时曲线都不受影响。
///
/// 版式与「切换连接」「选择配置文件」两个面板完全一致：同一套 `SheetSurface` 底色、
/// 同一种「标题 + 小字 + 圆形叉」的表头、同一种白底圆角行。三个面板走同一套
/// 底部 sheet，摆在一起就是同一个 App 的东西。
struct DeviceListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// 正在改名的设备 + 输入框内容。点一行就进这里。
    @State private var renaming: DeviceInfo?
    @State private var showRename = false
    @State private var draftName = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("连接设备", caption: headerCaption) {
                SheetCloseButton { dismiss() }
            }

            ScrollView {
                VStack(spacing: 0) {
                    if model.devices.isEmpty {
                        emptyState
                    } else {
                        // 用 IP 做标识：每轮采集都会重建 DeviceInfo，id 每次都不一样，
                        // 换成 IP 行才不会每 2 秒被整体重建一次。
                        SheetListCard {
                            ForEach(Array(model.devices.enumerated()), id: \.element.ip) { index, device in
                                if index > 0 {
                                    SheetRowDivider(leading: 14)
                                }
                                row(device)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    /// 卡片里的一行：名字 + IP · MAC / 铅笔。
    /// 以前每行单独一圈边框、左边还有一枚蓝底字母头像，和右边的铅笔一左一右，
    /// 名字被两个圆夹在中间成了配角。现在行合进一张卡，只留右侧铅笔。
    private func row(_ device: DeviceInfo) -> some View {
        let name = model.displayName(for: device)
        return Button {
            draftName = model.hasAlias(device) ? name : device.name
            renaming = device
            showRename = true
        } label: {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // IP 和 MAC 拆成两列：IP 给一个固定宽度（13 个等宽字符放得下），
                    // 后面那个「·」和 MAC 因此每行都从同一个 x 起步。
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
                    .foregroundStyle(.tertiary)
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，\(device.ip)，点按重命名")
    }
}
