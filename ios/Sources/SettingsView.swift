import SwiftUI
import UIKit

/// 设置页：顶部一张「路由器」卡把当前连接、切换、新建、编辑、网页后台全收进去，
/// 采集频率只留一行摘要，细项进二级页。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var confirmLogout = false
    @State private var editorRoute: ConnectionEditorRoute?
    @State private var showRouterWeb = false
    /// 切换连接的半屏选择器（自绘，不再用系统的列表/菜单）。
    @State private var showSwitcher = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader("设置") {
                        // 以前「重新连接」是路由器卡里的一个胶囊按钮，
                        // 新版式跟参考图一样只留三个动作，就把它收到页头，
                        // 和概览、网络代理两页的刷新按钮位置一致。
                        HeaderButton("arrow.clockwise") {
                            Task { await model.manualRefresh() }
                        }
                    }
                    routerCard
                        // 三个 sheet 挂在同一个视图上容易互相抢，网页后台这张挂到卡片上。
                        .sheet(isPresented: $showRouterWeb) {
                            if let url = model.routerWebURL {
                                PanelView(
                                    url: url,
                                    title: "路由器网页后台",
                                    autoLoginUser: model.currentProfile?.user,
                                    autoLoginPassword: model.currentPassword
                                )
                            }
                        }
                    appearanceCard
                    pollingCard
                    aboutCard
                    dangerCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.clear)
            // 见 OverviewView：标题画在内容里，导航栏整条不要。
            .toolbar(.hidden, for: .navigationBar)
            // 给底栏留白（见 App.swift 的 overlay 说明），最后一行不被玻璃栏遮住。
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: AppTabBar.contentBottomInset)
            }
            .sheet(item: $editorRoute) { route in
                ConnectionEditorView(profile: route.profile)
                    .id(route.id)
            }
            .sheet(isPresented: $showSwitcher) {
                RouterSwitcherSheet()
                    .environmentObject(model)
            }
            .confirmationDialog("退出后需要重新输入密码", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("断开并清除密码", role: .destructive) {
                    Task { await model.logout() }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 路由器（当前连接 + 三个动作 + 网页后台）

    /// 参照「图标 + 大标题 + 地址」的卡片版式重排：
    /// 上半部分是当前这台路由器是谁，下面一排三个等宽方块按钮，最后是一条整宽主按钮。
    private var routerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                // 状态不再占标题的宽度：参考图里标题是整行铺开的，
                // 右上角再挂一个「已连接」胶囊会把名字和地址挤成省略号。
                // 改成图标右下角一枚小圆点，颜色即状态。
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.blue.opacity(0.10))
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.22), lineWidth: 1)
                        // 与桌面图标同一枚线稿。58pt 的方块里放 26pt 时，
                        // 因为墨迹只有框高的七成，实际看着只有方块的 1/3 大，
                        // 四周空得发虚；38pt 才填到合适的分量。
                        RouterGlyph(size: 38)
                    }
                    .frame(width: 58, height: 58)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 13, height: 13)
                        .overlay {
                            Circle()
                                .strokeBorder(Color(.secondarySystemGroupedBackground),
                                              lineWidth: 2.5)
                        }
                        .offset(x: 2, y: 2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("路由器，\(statusLabel)")

                VStack(alignment: .leading, spacing: 4) {
                    Text(routerTitle)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(routerSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            Divider().opacity(0.5)

            HStack(spacing: 9) {
                actionTile("切换连接", icon: "arrow.left.arrow.right",
                           enabled: !model.profiles.isEmpty) {
                    showSwitcher = true
                }
                actionTile("新建连接", icon: "plus") {
                    openEditor(nil)
                }
                actionTile("编辑当前连接", icon: "pencil",
                           enabled: model.currentProfile != nil) {
                    openEditor(model.currentProfile ?? model.profiles.first)
                }
            }

            Button {
                showRouterWeb = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                    Text("打开路由器网页后台")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    canOpenWeb ? Color.blue : Color.blue.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(canOpenWeb ? Color.white : Color.secondary)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canOpenWeb)

            autoLoginRow

            // 错误提示：8 秒自动消失，也能点叉立刻收掉。
            // 以前只在「下一次连接成功」时才清，连不上的红字会一直挂在设置页上，
            // 除非退出 App 重进——这就是截图里那行一直不走的报错。
            if let error = model.errorMessage {
                ErrorBanner(text: error) { model.clearError() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var canOpenWeb: Bool {
        model.routerWebURL != nil
    }

    private var routerTitle: String {
        model.currentProfile?.title ?? "还没有连接"
    }

    /// 参考图那行：`root@192.168.8.1:22 · 网页 :8080`。
    private var routerSubtitle: String {
        guard let profile = model.currentProfile else {
            return "点「新建连接」填地址和密码"
        }
        return "\(profile.user)@\(profile.host):\(profile.port) · 网页 :\(profile.webPortValue)"
    }

    /// 三个等宽方块按钮：图标在上、文字在下。
    ///
    /// 以前中间「新建连接」单独用深一档的蓝底 + 蓝字 + 蓝描边当主按钮，
    /// 结果三块里有一块像另一套控件，摆在一起更像被选中了。现在三块完全同色、
    /// 同高、同描边，主次只靠位置（新建排中间）和文案表达。
    private func actionTile(_ title: String, icon: String,
                            enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                // 三个图标的「自带高度」并不一样（arrow.left.arrow.right 比 plus 高约 6pt），
                // 不框住的话三个盒子就一高一矮。这里统一给 20pt 的框，高度就一致了。
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .softTile(.blue, radius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private var autoLoginRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "key.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text("启动时自动连接")
                .font(.footnote)
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(
                get: { model.autoLogin },
                set: { model.autoLogin = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    /// 图标角标：正在连新连接时旧会话还在，别让绿点骗人。
    private var statusColor: Color {
        if model.connecting { return .blue }
        return model.connected ? .green : .orange
    }

    private var statusLabel: String {
        if model.connecting { return "正在连接" }
        return model.connected ? "已连接" : model.status
    }

    private func openEditor(_ profile: RouterProfile?) {
        editorRoute = profile.map(ConnectionEditorRoute.edit) ?? .new
    }


    // MARK: - 外观

    private struct ThemeOption: Identifiable {
        let id: String
        let title: String
    }

    private var themeOptions: [ThemeOption] {
        [ThemeOption(id: "system", title: "跟随系统"),
         ThemeOption(id: "light", title: "浅色"),
         ThemeOption(id: "dark", title: "深色")]
    }

    private var appearanceCard: some View {
        SectionCard("外观", icon: "circle.lefthalf.filled") {
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(themeOptions) { option in
                        Button {
                            themeMode = option.id
                        } label: {
                            Text(option.title)
                                .font(.subheadline.weight(themeMode == option.id ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    themeMode == option.id
                                        ? Color.blue.opacity(0.16)
                                        : Color.blue.opacity(0.05),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            themeMode == option.id
                                                ? Color.blue.opacity(0.45)
                                                : Color.blue.opacity(0.14),
                                            lineWidth: 1
                                        )
                                }
                                .foregroundStyle(themeMode == option.id ? Color.blue : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().opacity(0.5)

                NavigationLink {
                    ModuleSettingsView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("概览模块").font(.subheadline)
                            Text("显示或隐藏卡片、拖动排序")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 采集与刷新（摘要，细则进二级页）

    private var pollingCard: some View {
        SectionCard("采集与刷新", icon: "clock.arrow.circlepath") {
            NavigationLink {
                PollSettingsView()
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("每 \(Int(model.pollSeconds.rounded())) 秒")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(PollItem.allCases.count) 项数据，只采当前页面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        ForEach(AppPage.allCases) { page in
                            pageChip(page)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 一眼看出「哪一页采哪些数据」，比之前三档的格子干净得多。
    private func pageChip(_ page: AppPage) -> some View {
        let count = model.pollConfig.items(on: page).count
        let active = page == model.activePage && count > 0
        return HStack(spacing: 4) {
            Image(systemName: page.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(count > 0 ? "\(page.title) \(count) 项" : "\(page.title) 不采集")
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            active ? Color.blue.opacity(0.16) : Color.blue.opacity(0.05),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(active ? Color.blue.opacity(0.4) : Color.blue.opacity(0.12),
                              lineWidth: 1)
        }
        .foregroundStyle(active ? Color.blue : Color.secondary)
    }

    // MARK: - 关于

    /// 平时只留两行：版本 + 连接方式。
    /// 只有真的跑在「兼容窗口」里（系统按旧尺寸排版、四周留黑边）时，
    /// 才临时多出一行说明——不然用户只能看到黑边，却不知道是打包 SDK 的问题。
    private var aboutCard: some View {
        SectionCard("关于", icon: "info.circle") {
            VStack(spacing: 10) {
                infoRow("版本", appVersion)
                Divider().opacity(0.5)
                infoRow("连接方式", "SSH 直连")
                if let note = compatWindowNote {
                    Divider().opacity(0.5)
                    VStack(alignment: .leading, spacing: 4) {
                        infoRow("显示适配", "未铺满", color: .orange)
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(Color(.tertiaryLabel))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("系统按打包用的 SDK 决定窗口档位，用 Xcode 27（iOS 27 SDK）重新打包即可铺满。")
                            .font(.caption2)
                            .foregroundStyle(Color(.tertiaryLabel))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 版本号从包里读，别在界面上再抄一份——抄的那份早晚和工程文件对不上。
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    /// 兼容窗口的判断：逻辑尺寸比「原生像素 ÷ 缩放」小一圈，就是被系统塞进旧尺寸窗口了。
    /// 这时屏幕上下（个别机型还有左右）会留黑边，App 自己铺不出去。
    private var compatWindowNote: String? {
        guard let screen = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.screen else { return nil }
        let native = screen.nativeBounds.size
        let physical = CGSize(width: native.width / screen.nativeScale,
                              height: native.height / screen.nativeScale)
        let logical = screen.bounds.size
        guard physical.width - logical.width > 1 || physical.height - logical.height > 1 else {
            return nil
        }
        let sdk = (Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String) ?? "未知 SDK"
        return String(
            format: "界面按 %.0f×%.0f 排版，屏幕是 %.0f×%.0f · 打包 %@",
            logical.width, logical.height, physical.width, physical.height, sdk
        )
    }

    private func infoRow(_ title: String, _ value: String,
                         color: Color = .secondary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var dangerCard: some View {
        VStack(spacing: 10) {
            Button {
                confirmLogout = true
            } label: {
                Text("断开并清除密码")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)

            Text("清空后需要重新输入密码才能连接，保存的监控设置不会丢。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}

// MARK: - 卡片容器

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            content
        }
        .glassCard()
    }
}

// MARK: - 切换连接

/// 已保存的连接列表：点一行就切换，右侧垃圾桶删掉。
///
/// 原来是「每行一块圆角卡 + 蓝边」竖着排，一屏三行像贴了三张便利贴，
/// 而面板固定半屏高，只有一条记录时下半屏全是空白——所以看着又碎又空。
/// 现在改成系统设置那种分组列表（行合进一张卡、行间缩进细线），
/// 高度按条数算（`presentationDetents` 用 `.height`），有几条就多高。
private struct RouterSwitcherSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: RouterProfile?
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader("切换连接", caption: caption) {
                SheetCloseButton { dismiss() }
            }

            ScrollView {
                VStack(spacing: 16) {
                    if model.profiles.isEmpty {
                        emptyCard
                    } else {
                        SheetListCard {
                            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                                if index > 0 {
                                    SheetRowDivider(leading: 58)
                                }
                                row(profile)
                            }
                        }
                    }

                    Text("点一行立即切换；删除会一并清掉钥匙串里的密码。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(SheetSurface())
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            pendingDelete.map { "删除「\($0.title)」？" } ?? "删除这个连接？",
            isPresented: $confirmDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { profile in
            Button("删除连接", role: .destructive) {
                model.deleteProfile(profile)
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { profile in
            Text(profile.id == model.currentProfileID
                 ? "这是当前正在使用的连接，删除后会立即断开，需要重新填写密码。"
                 : "密码会一起从钥匙串里删除，重新添加时要再输一次。")
        }
    }

    private var caption: String {
        model.profiles.isEmpty
            ? "还没有保存过连接"
            : "共 \(model.profiles.count) 个，点一下即切换"
    }

    /// 面板高度跟着条数走：表头 70 + 每行 64 + 说明 36 + 上下留白 38。
    /// 只有一条记录时不再撑出半屏空白；八条以上就顶到 560 由 ScrollView 接管。
    /// 空状态那张卡比一行高得多（有图标和两行说明），单独给 300。
    private var sheetHeight: CGFloat {
        guard !model.profiles.isEmpty else { return 300 }
        let rows = CGFloat(model.profiles.count)
        return min(max(70 + rows * 64 + 36 + 38, 216), 560)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "router")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("还没有保存过连接")
                .font(.subheadline.weight(.medium))
            Text("回到设置页点「新建连接」，填好路由器地址和密码即可")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .background(
            Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.55), lineWidth: 0.5)
        }
    }

    private func row(_ profile: RouterProfile) -> some View {
        let isCurrent = profile.id == model.currentProfileID
        let isConnecting = model.connecting
            && model.attemptTarget?.profile.id == profile.id

        return HStack(spacing: 0) {
            Button {
                guard !isCurrent, !isConnecting else { return }
                // 先收起面板，让连接弹窗能盖在最上面。
                dismiss()
                Task { await model.switchTo(profile) }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isCurrent ? Color.blue.opacity(0.16) : Color(.tertiarySystemFill))
                            .frame(width: 34, height: 34)
                        // 原来靠「实心 / 空心」区分当前连接，线稿没有实心版，
                        // 改用颜色：当前那台给主色，其余降到次要灰。
                        RouterGlyph(size: 22,
                                    tint: isCurrent ? Color.blue : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(profile.title)
                                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isCurrent {
                                Text("当前")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(profile.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)

                    if isConnecting {
                        ProgressView().controlSize(.mini)
                    } else if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(minHeight: 64)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 这里**不能**用 `.disabled(isCurrent)`：禁用会把整行 label 压淡，
            // 当前那一行因此像蒙了一层灰（用户就是这么反馈的）。
            // 当前行和「正在连」本来就被上面的 guard 挡住了，不需要禁用态。

            Button {
                pendingDelete = profile
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel("删除 \(profile.title)")
        }
    }
}

// MARK: - 连接编辑

/// 编辑器要打开哪一种：新建，还是编辑某一个已保存的连接。
///
/// 之前用 `showEditor` 布尔 + 单独的 `editProfile` 两个状态驱动 `.sheet(isPresented:)`，
/// 点「编辑」时 sheet 的内容闭包可能拿到还没写入的旧值（nil），于是第一次点开
/// 总是「新建连接」。改成用 item 驱动，数据本身决定弹窗，就不会再错位。
private enum ConnectionEditorRoute: Identifiable {
    case new
    case edit(RouterProfile)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let profile): return profile.id.uuidString
        }
    }

    var profile: RouterProfile? {
        switch self {
        case .new: return nil
        case .edit(let profile): return profile
        }
    }
}

private struct ConnectionEditorView: View {
    let profile: RouterProfile?
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var host: String
    @State private var port: String
    @State private var webPort: String
    @State private var user: String
    @State private var password: String

    init(profile: RouterProfile?) {
        self.profile = profile
        _label = State(initialValue: profile?.label ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: String(profile?.port ?? 22))
        _webPort = State(initialValue: String(profile?.webPortValue ?? 80))
        _user = State(initialValue: profile?.user ?? "root")
        _password = State(initialValue: profile.flatMap {
            KeychainStore.loadPassword(account: KeychainStore.passwordAccount(for: $0))
        } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接信息") {
                    TextField("连接名称（可选）", text: $label)
                    TextField("路由器地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("SSH 端口", text: $port)
                        .keyboardType(.numberPad)
                    TextField("网页后台端口（LuCI）", text: $webPort)
                        .keyboardType(.numberPad)
                    TextField("用户名", text: $user)
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $password)
                }

                Section {
                    Button {
                        Task {
                            let sshPort = Int(port) ?? 22
                            let web = Int(webPort) ?? 80
                            if let profile {
                                await model.updateProfile(
                                    profile,
                                    host: host,
                                    port: sshPort,
                                    user: user,
                                    password: password,
                                    label: label,
                                    webPort: web
                                )
                            } else {
                                await model.saveNewProfile(
                                    host: host,
                                    port: sshPort,
                                    user: user,
                                    password: password,
                                    label: label,
                                    webPort: web
                                )
                            }
                            // 连上了就收起表单；失败则留在这里让用户改地址，
                            // 上一台连接已经自动恢复，关掉也不会掉线。
                            if model.connected && !model.lastConnectFailed { dismiss() }
                        }
                    } label: {
                        HStack {
                            if model.connecting { ProgressView() }
                            Text(model.connecting ? "正在连接…" : "连接并保存")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(model.connecting || host.isEmpty || password.isEmpty)
                }

                if let error = model.errorMessage {
                    Section {
                        ErrorBanner(text: error) { model.clearError() }
                    }
                }
            }
            .navigationTitle(profile == nil ? "新建连接" : "编辑连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
