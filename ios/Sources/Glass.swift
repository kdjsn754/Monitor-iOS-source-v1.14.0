import SwiftUI

/// Lightweight, flat surface styling. No blur/material layers, so scrolling
/// stays smooth on older iPhones.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.035, green: 0.05, blue: 0.075),
                    Color(red: 0.055, green: 0.075, blue: 0.11)
                ]
                : [
                    Color(red: 0.985, green: 0.99, blue: 1.0),
                    Color(red: 0.945, green: 0.965, blue: 0.99)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.55), lineWidth: 0.5)
            }
    }
}

extension View {
    func glassCard(padding: CGFloat = 16,
                   cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

/// 卡片里的「小块底色」。
///
/// 以前这些格子一律用 `Color(.tertiarySystemFill)`——一块偏冷的灰。
/// 白卡上叠几块灰，页面看着像没做完：灰和主色蓝不是一族，格子多的时候整页发脏。
/// 现在改成「同色极浅填充 + 同色细描边」：填的是每个格子自己的主色（CPU 橙、内存靛、
/// 下载蓝、上传紫…），块面感还在，颜色也和图标、数字对上了。
/// 深色模式下提一点不透明度，否则叠在深色卡上会看不见。
struct SoftTileModifier<S: InsettableShape>: ViewModifier {
    let color: Color
    let shape: S

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(color.opacity(colorScheme == .dark ? 0.16 : 0.05))
            }
            .overlay {
                shape.strokeBorder(color.opacity(colorScheme == .dark ? 0.28 : 0.15),
                                   lineWidth: 1)
            }
    }
}

extension View {
    /// 任意形状的浅色底。
    func softTile<S: InsettableShape>(_ color: Color = .blue, in shape: S) -> some View {
        modifier(SoftTileModifier(color: color, shape: shape))
    }

    /// 圆角矩形的浅色底（最常用）。
    func softTile(_ color: Color = .blue, radius: CGFloat = 12) -> some View {
        softTile(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 面板 / 卡片里的「行」：和卡片同色 + 一圈细边。
///
/// 这些行以前用 `softTile(.blue)`：5% 蓝底 + 15% 蓝边。一行两行还像块面，
/// 一屏四五行叠起来整片发蓝，跟卡片的白底互相打架，行里的 IP / MAC 也被衬得发蓝，
/// 看着像「一排提示卡」而不是普通列表。
/// 现在统一回到白底黑字：填充就是 `systemBackground`（和卡片同色），
/// 只留一圈 `separator` 细边划出行界。
///
/// 深色模式不能再跟浅色一样取 `systemBackground`——那是**纯黑**（#000），
/// 而外层卡片是 `secondarySystemGroupedBackground`（#1C1C1E），黑行压在深灰卡上
/// 会像挖了一个洞，行与卡片的边界比文字还抢眼。深色用 `tertiarySystemBackground`
/// （#2C2C2E）比卡片亮一档，层级才对。
/// `emphasized` 只给「当前选中的那一行」用：不铺蓝底，只把边线换成主色。
struct RowTileModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var emphasized: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(colorScheme == .dark
                           ? Color(.tertiarySystemBackground)
                           : Color(.systemBackground))
            }
            .overlay {
                shape.strokeBorder(
                    emphasized ? Color.blue.opacity(0.5) : Color(.separator),
                    lineWidth: emphasized ? 1.3 : 0.75
                )
            }
    }
}

extension View {
    func rowTile<S: InsettableShape>(in shape: S, emphasized: Bool = false) -> some View {
        modifier(RowTileModifier(shape: shape, emphasized: emphasized))
    }

    func rowTile(radius: CGFloat = 14, emphasized: Bool = false) -> some View {
        rowTile(in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                emphasized: emphasized)
    }
}

/// 半屏面板的底色。
///
/// 以前是「白底 + 3.5% 主色」，想让面板和 App 渐变背景同一个色系。但行块本身
/// 也带一层浅蓝底，两层叠起来整片发蓝，黑字压在上面都显灰。
/// 现在面板回到纯白（跟着系统 background 走），层次全靠行的那一圈细边划分。
struct SheetSurface: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

/// 页面大标题，直接画在内容里，不用系统的大标题。
///
/// 系统大标题占的位置很死：状态栏 59pt + 导航栏 44pt + 标题，标题顶边要到屏幕
/// 109pt 才出现，中间那几十 pt 全是空白。自己排之后标题顶边在 63pt 左右，
/// 省下将近 46pt，也不会再有导航栏那条材质和内容之间的接缝。
struct PageHeader<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 2)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// 标题右边的小圆按钮（刷新之类），代替原来导航栏右上角的图标。
///
/// iOS 26 起用系统液态玻璃（`glassEffect`）：玻璃会自己把背后的页面渐变、卡片
/// 折进按钮里，按下还有回弹式的形变，和系统自己的玻璃按钮一致。
/// 之前的「蓝线 + 5% 蓝底」在 iOS 26 的页面上显得很平，像贴上去的贴纸。
/// 低于 iOS 26 的机器退回原来那枚浅蓝圆钮，不会掉成灰按钮。
struct HeaderButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    init(_ systemImage: String, label: String = "刷新", action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .modifier(HeaderButtonSurface())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct HeaderButtonSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // interactive：按下时玻璃会被按下去一点，松手弹回，不用自己写按压态。
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.softTile(.blue, in: Circle())
        }
    }
}

/// 一条可关闭的错误提示。
///
/// 旧版把错误直接当三行红字贴在卡片底部，既占地方又不会自己消失。
/// 现在收成一条浅红底的横幅：最多两行、带叉，点掉就没了。
struct ErrorBanner: View {
    let text: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 20, height: 20)
                        .background(Color.red.opacity(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭提示")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.red.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Color.blue, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// 居中的对话框容器：一层半透明遮罩把背后的页面压暗，中间放一张圆角卡片。///
/// 以前「连接设备 / 选择配置文件 / 切换连接」都是底部浮层（`.sheet` + 拖拽条），
/// 在 iPhone 上只能从底边长出来、还常把最后一行内容压在下面。改成这种居中弹窗后，
/// 内容是浮在页面正中的卡片，四周留白一致，文字和对齐也好排；点遮罩任意处即可关闭。
struct CenteredModal<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            content()
                .frame(maxWidth: 460)
                .padding(.horizontal, 16)
        }
    }
}

/// 居中对话框用的卡片底：和页面卡片同一套白底 + 细边，外加一圈柔和的投影
/// 把它从遮罩里「托」起来，看着像浮在上面的面板而不是贴上去的。
struct ModalCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 30, y: 14)
    }
}

// MARK: - 底部面板的公共骨架

/// 底部面板的统一表头：左边「标题 + 一行小字」，右边一个圆形按钮。
///
/// 之前三个面板各自复制了一份一模一样的表头代码，改一处要同步三处，
/// 而且右侧的关闭叉是三份淡蓝小圆圈——系统面板里那是灰的，蓝色圆圈在
/// 白底上像一枚「操作按钮」，点下去之前看不出它只是关闭。
struct SheetHeader<Trailing: View>: View {
    private let title: String
    private let caption: String
    private let trailing: Trailing

    init(_ title: String, caption: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

extension SheetHeader where Trailing == EmptyView {
    init(_ title: String, caption: String) {
        self.init(title, caption: caption) { EmptyView() }
    }
}

/// 表头右上角那枚关闭叉：灰底圆，和系统面板一致。
struct SheetCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }
}

/// 表头右上角的小图标按钮（刷新之类），跟关闭叉同一套尺寸。
struct SheetIconButton: View {
    let systemImage: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 面板里的「一块列表」：多行合进一张卡片，行间用缩进细线隔开。
///
/// 以前每行都是独立的圆角块 + 一圈边框，三行下来像三张便利贴并排；
/// 合起来之后才像系统里的分组列表。
///
/// 底色从 `secondarySystemBackground`（浅色下是 #F2F2F7 的一整块灰）改成纯白：
/// 白面板 + 灰卡片这一层，行里的名字、IP 全被那块灰衬得发闷，四行以上整片糊成一块，
/// 黑字也显灰。现在卡片和面板同色，靠一圈 hairline 描边 + 缩进分隔线划分行，
/// 就是「白底黑字」该有的样子。
struct SheetListCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                Color(.systemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.55), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 面板里的「分区卡」：图标 + 小标题在上，内容在下，白底 + 细边。
///
/// 主页面用的 `SectionCard` 走 `glassCard`，在渐变背景上是 `secondarySystemGroupedBackground`
/// 的浅灰卡；这套色挪进面板就成了「白面板上压一堆灰方块」——正是用户说的那层灰。
/// 面板里一律换成白底，只留 0.5pt 的边。
struct SheetSectionCard<Content: View>: View {
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
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.systemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.55), lineWidth: 0.5)
        }
    }
}

/// 列表卡片里的分隔线：从文字起始处开始，不顶到卡片边缘。
struct SheetRowDivider: View {
    var leading: CGFloat = 58

    var body: some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.6))
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}
