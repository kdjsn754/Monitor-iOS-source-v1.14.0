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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.blue)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
