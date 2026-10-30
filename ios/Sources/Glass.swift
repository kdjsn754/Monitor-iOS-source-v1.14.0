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

/// 面板 / 卡片里的「行」：白底 + 一圈细边。
///
/// 这些行以前用 `softTile(.blue)`：5% 蓝底 + 15% 蓝边。一行两行还像块面，
/// 一屏四五行叠起来整片发蓝，跟卡片的白底互相打架，行里的 IP / MAC 也被衬得发蓝，
/// 看着像「一排提示卡」而不是普通列表。
/// 现在统一回到白底黑字：填充就是 `systemBackground`（和卡片同色），
/// 只留一圈 `separator` 细边划出行界；深色模式跟着系统走，不用另配一套色。
/// `emphasized` 只给「当前选中的那一行」用：不铺蓝底，只把边线换成主色。
struct RowTileModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(Color(.systemBackground))
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
