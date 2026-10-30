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
///
/// **改名与删除确认都是面板内自绘的卡片，不用系统 alert / confirmationDialog。**
/// 在 sheet 内部弹这两个系统弹窗，iOS 26 会把浮层锚到页面上方、或者干脆不出现
/// （用户原话：「删除这个弹窗弹出的位置不对，点铅笔编辑没反应」）。
/// 自绘一层遮罩 + 卡片，位置永远落在这一屏正中，样式也和其他自绘面板统一。
struct DeviceListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// 正在改名的设备。非 nil 就把改名卡片浮起来。
    @State private var editing: DeviceInfo?
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    /// 待删除的设备：点单个是 1 台，点右上角是全部离线。
    /// 非空就浮确认卡片，文案按数量变——不用再维护一个「要不要弹」的布尔。
    @State private var pendingRemove: [DeviceInfo] = []

    /// 改名时把面板撑到全屏：半屏 + 键盘，输入框会被挤得只剩一条缝。
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("连接设备", caption: headerCaption) {
                HStack(spacing: 8) {
                    // 只有存在离线设备时才出现垃圾桶，全在线的时候这里不该有能点的东西。
                    if model.offlineDeviceCount > 0 {
                        SheetIconButton(systemImage: "trash", label: "清理离线设备") {
                            editing = nil
                            pendingRemove = model.devices.filter { !$0.online }
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
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .overlay { modalLayer }
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

    // MARK: - 面板内的浮层

    /// 一层遮罩 + 一张卡片。点遮罩关闭，点卡片本身不关闭。
    @ViewBuilder
    private var modalLayer: some View {
        if let device = editing {
            SheetOverlay(onDismiss: closeModals) { renameCard(device) }
        } else if let first = pendingRemove.first {
            SheetOverlay(onDismiss: closeModals) {
                removeCard(count: pendingRemove.count, first: first)
            }
        }
    }

    private func renameCard(_ device: DeviceInfo) -> some View {
        SheetOverlayCard {
            VStack(alignment: .leading, spacing: 3) {
                Text("重命名设备")
                    .font(.headline)
                Text("原名 \(device.name) · \(device.ip)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextField("设备名称", text: $draftName)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { commitRename(device) }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if model.hasAlias(device) {
                Button {
                    model.setDeviceAlias("", for: device)
                    closeModals()
                } label: {
                    Text("恢复原名")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                SheetOverlayButton(title: "取消") { closeModals() }
                SheetOverlayButton(title: "保存", tint: .blue) { commitRename(device) }
            }
        }
    }

    private func removeCard(count: Int, first: DeviceInfo) -> some View {
        SheetOverlayCard {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
                    .background(Color.red.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? "删除这台设备？" : "删除 \(count) 台设备？")
                        .font(.headline)
                    if count == 1 {
                        Text(first.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Text("只从这台手机的列表里移除，路由器上的租约不受影响。设备重新连上会自己出现。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                SheetOverlayButton(title: "取消") { closeModals() }
                SheetOverlayButton(title: count == 1 ? "删除" : "删除 \(count) 台",
                                   tint: .red) {
                    model.removeDevices(pendingRemove)
                    closeModals()
                }
            }
        }
    }

    // MARK: - 动作

    private func beginRename(_ device: DeviceInfo, _ name: String) {
        draftName = model.hasAlias(device) ? name : device.name
        pendingRemove = []
        editing = device
        detent = .large
        // 立刻聚焦有时会被面板动画吃掉，等一拍再点，键盘才跟得上。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            nameFocused = true
        }
    }

    private func commitRename(_ device: DeviceInfo) {
        model.setDeviceAlias(draftName, for: device)
        closeModals()
    }

    private func closeModals() {
        nameFocused = false
        editing = nil
        pendingRemove = []
    }
}
