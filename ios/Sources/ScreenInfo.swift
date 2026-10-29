import UIKit

/// 屏幕与「是否被系统按兼容模式缩放」的运行环境信息。
///
/// 为什么需要它：用低于机型代数的 SDK 打包时，系统不认识这块屏，会把 App 按上一代
/// 的逻辑尺寸排版，再整体放大到物理像素上——表现就是内容缩在中间、上下各留一条黑边。
/// 这种情况只靠改界面救不回来（窗口大小由系统决定），必须换新 Xcode 重新打包。
///
/// 判据很直接：`nativeBounds.width / bounds.width` 应该正好等于 `scale`（3×）。
/// 一旦大于 3，说明界面被放大过，也就是正处在兼容模式。
enum ScreenInfo {
    struct Snapshot {
        var size = CGSize.zero
        var native = CGSize.zero
        var scale: CGFloat = 0
        var renderedScale: CGFloat = 0

        var isValid: Bool { size.width > 0 && native.width > 0 }

        /// 被系统放大渲染（兼容模式）。
        var isLetterboxed: Bool {
            guard isValid, scale > 0 else { return false }
            return renderedScale > scale + 0.001
        }

        /// 「402 × 874 pt · 3×」
        var sizeText: String {
            guard isValid else { return "--" }
            let w = Int(size.width.rounded())
            let h = Int(size.height.rounded())
            return "\(w) × \(h) pt · \(String(format: "%.0f", scale))×"
        }

        /// 兼容模式时给出放大倍数，正常时给「原生全屏」。
        var modeText: String {
            guard isValid else { return "--" }
            if isLetterboxed {
                return String(format: "兼容模式（放大 %.2f×）", renderedScale / max(scale, 1))
            }
            return "原生全屏"
        }
    }

    static var current: Snapshot {        var snapshot = Snapshot()
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return snapshot
        }
        let screen = scene.screen
        snapshot.size = screen.bounds.size
        snapshot.native = screen.nativeBounds.size
        snapshot.scale = screen.scale
        if snapshot.size.width > 0 {
            snapshot.renderedScale = snapshot.native.width / snapshot.size.width
        }
        return snapshot
    }

    /// 打包时用的 SDK，例如 `iphoneos26.0`。
    ///
    /// 这是判断「黑边是不是 SDK 老了」最直接的证据：低于 iphoneos26 就一定是旧工具链打的包。
    static var sdkName: String {
        (Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String) ?? "--"
    }
}
