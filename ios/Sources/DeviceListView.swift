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
    /// 正在改名的设备 + 输入框内容。点行尾的铅笔才进这里。
    @State private var renaming: DeviceInfo?
    @State private var showRename = false
    @State private var draftName = ""
    /// 待删除的设备：点单个是 1 台，点右上角是全部离线。确认框共用一份，
    /// 标题和按钮文案按数量变，不用维护两个弹窗状态。
    @State private var pendingRemove: [DeviceInfo] = []
    @State private var confirmRemove = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("连接设备", caption: headerCaption) {
                HStack(spacing: 8) {
                    // 只有存在离线设备时才出现垃圾桶，全在线的时候这里不该有能点的东西。
                    if model.offlineDeviceCount > 0 {
                        SheetIconButton(systemImage: "trash", label: "清理离线设备") {
                            pendingRemove = model.devices.filter { !$0.online }
                            confirmRemove = true
                        }
                    }
                    SheetCloseButton { dismiss() }
                }
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
        .confirmationDialog("删除离线设备", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("删除 \(pendingRemove.count) 台设备", role: .destructive) {
                model.removeDevices(pendingRemove)
                pendingRemove = []
            }
            Button("取消", role: .cancel) { pendingRemove = [] }
        } message: {
            // 说清楚「删的是什么」：只删本机列表里的记录，不碰路由器的租约文件。
            // 设备重新连上会自己回到列表，所以这一步不是不可逆的。
            Text("只从这台手机的列表里移除，路由器上的租约不受影响。设备重新连上会自己出现。")
        }
    }

    private var headerCaption: String {
        guard !model.devices.isEmpty else {
            return model.hiddenDeviceCount > 0
                ? "已清理 \(model.hiddenDeviceCount) 台离线设备"
                : "DHCP 租约里还没有设备"
        }
        let offline = model.offlineDeviceCount
        let online = model.devices.count - offline
        // 以前这里写的是「N 台在线」，数字其实是租约条数。租约 12 小时才过期，
        // 关掉的设备也算在里面，于是这句标题天天在骗人。现在分开说。
        if offline == 0 { return "\(online) 台在线 · 点铅笔可改名" }
        return "\(online) 台在线 · \(offline) 台离线 · 点铅笔可改名"
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hiddenDeviceCount > 0 {
            // 全被清掉的时候不能再说「暂无设备」，否则用户会以为清理把设备弄丢了。
            SheetEmptyState(icon: "eye.slash",
                            title: "离线设备已清理",
                            message: "去「设置 → 设备列表」可以一键恢复",
                            verticalPadding: 34)
        } else {
            SheetEmptyState(icon: "wifi.slash",
                            title: "暂无 DHCP 租约设备",
                            verticalPadding: 34)
        }
    }

    /// 卡片里的一行：状态点 + 名字 + IP · MAC / 铅笔（离线行多一个垃圾桶）。
    ///
    /// **只有右侧图标是按钮**，名字和地址那一块是纯文字、点了什么也不发生。
    /// 之前把整块文字区包成 Button，本意是「点名字改名」，实际用起来是
    /// 手指在行里随便一按就弹出改名框 —— 这块面积占了一行的八成，
    /// 想滚动列表、想看一眼 MAC，都会误触。改名不是高频动作，
    /// 收到铅笔上更符合直觉，也让滚动时不再有「按下变淡」的干扰。
    private func row(_ device: DeviceInfo) -> some View {
        let name = model.displayName(for: device)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // 6pt 的小圆点：绿=此刻真连着，灰=只有租约、人已经走了。
                    // 不用色块也不用边框，一行里只让这一个点变色。
                    Circle()
                        .fill(device.online ? Color.green : Color(.systemGray3))
                        .frame(width: 6, height: 6)
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        // 离线行整块压一档，扫一眼就能分出在线与离线两组。
                        .foregroundStyle(device.online
                                         ? Color(uiColor: .label)
                                         : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // IP 和 MAC 拆成两列：IP 给一个固定宽度（13 个等宽字符放得下），
                // 后面那个「·」和 MAC 因此每行都从同一个 x 起步。
                // 12pt 左缩进是为了跟上一行的名字左边缘对齐——圆点单独悬在左边，
                // 名字和 IP 都从同一条线开始，四行扫下来不会一边多一块一边少一块。
                HStack(spacing: 6) {
                    Text(device.ip)
                        .frame(minWidth: 88, alignment: .leading)
                    Text("·")
                    Text(device.mac.uppercased())
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !device.online {
                Button {
                    pendingRemove = [device]
                    confirmRemove = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除 \(name)")
            }

            Button {
                beginRename(device, name)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    // 铅笔现在是唯一的改名入口，不能再用 tertiary（太淡，看不出能点），
                    // 降一档到 secondary，和旁边垃圾桶同一个视觉重量。
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重命名 \(name)")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private func beginRename(_ device: DeviceInfo, _ name: String) {
        draftName = model.hasAlias(device) ? name : device.name
        renaming = device
        showRename = true
    }
}
