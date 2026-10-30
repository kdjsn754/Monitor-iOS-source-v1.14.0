import Foundation
import SwiftUI

/// App 内统一使用的路由器线稿。
///
/// 和桌面图标（`Assets.xcassets/AppIcon.appiconset/icon-1024.png`）是同一套几何：
/// 方盒 + 两根天线 + 大小两道弧 + 面板线 + 指示灯。那枚图标的画布是 1024，
/// 图形内容（含笔宽）宽 562；这里把同一组坐标按比例画进任意尺寸的框里，
/// 线条粗细固定为图形宽度的 4.6% —— 这样 19pt 的列表行和 34pt 的卡片图标
/// 是同一枚图形，不会像 SF Symbols 那样换个字号就换一种粗细。
///
/// 小尺寸会掉细节：低于 24pt 时面板线和指示灯会糊成一片浅灰，这时只保留盒子、
/// 天线和两道弧（仍能认出是路由器）。
struct RouterGlyph: View {
    var size: CGFloat
    var tint: Color = .blue

    /// 面板线与指示灯至少要这么多点才画得清。
    private var showsDetails: Bool { size >= 24 }

    private var lineWidth: CGFloat {
        // 4.6% 是图标里的比例（笔宽 26 / 内容 562）；细到 1.25pt 以下就发虚，给个下限。
        max(1.25, size * 0.046)
    }

    var body: some View {
        ZStack {
            RouterGlyphShape(showsDetails: showsDetails)
                .stroke(tint,
                        style: StrokeStyle(lineWidth: lineWidth,
                                           lineCap: .round,
                                           lineJoin: .round))
            if showsDetails {
                RouterGlyphLamp().fill(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 几何

/// 图标坐标 → 目标框的换算。
///
/// 原图是 1024 画布，那枚图标里图形整体上移过 38pt 才视觉居中，
/// 这里直接沿用上移后的坐标，省得两处各算一遍。
private enum RouterGeometry {
    /// 图形内容的边长：机身最宽，536 + 两侧各半个笔宽 = 562。
    /// 注意别按天线的跨度去算 —— 天线（306…718）比机身窄，按它裁会把机身两边切掉。
    static let content: CGFloat = 562
    /// 内容中心：x 居中，y 由「主弧最高点 325」与「机身底边 716」取中。
    static let center = CGPoint(x: 512, y: 520.5)

    static func transform(in rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / content
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
    }

    /// 朝上凸的圆弧：圆心一定在弦的下方。
    ///
    /// 这里**不用** `Path.addArc(center:radius:startAngle:endAngle:clockwise:)`。
    /// 那个 API 的 `clockwise` 在 SwiftUI 的翻转坐标系里方向是反的：起角 -129°、
    /// 终角 -51° 时它不会走「经过 -90°（正上方）」的那一小段，而是绕远路从下方兜一圈，
    /// 两道弧于是变成一只闭合的「眼睛」——2026-10-30 实机上就是这个样子。
    /// 改成按角度等分取点连折线：方向由我们自己定，48 段在 34pt 下已经看不出棱角。
    static func addArc(_ path: inout Path, from a: CGPoint, to b: CGPoint, radius: CGFloat) {
        let ax = Double(a.x), ay = Double(a.y)
        let bx = Double(b.x), by = Double(b.y)
        let r = Double(radius)

        let mx = (ax + bx) / 2, my = (ay + by) / 2
        let half = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot() / 2
        // 半径比弦还短时开方会得到 NaN，夹一下免得整条路径失效。
        let height = (max(0, r * r - half * half)).squareRoot()
        // 圆心在弦的下方（y 越大越靠下），弧才是往上凸的。
        let cy = my + height

        let start = atan2(ay - cy, ax - mx)
        let end = atan2(by - cy, bx - mx)

        let steps = 48
        for i in 0...steps {
            let t = start + (end - start) * Double(i) / Double(steps)
            let point = CGPoint(x: mx + r * cos(t), y: cy + r * sin(t))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
    }
}

private struct RouterGlyphShape: Shape {
    var showsDetails: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 机身
        path.addRoundedRect(in: CGRect(x: 244, y: 503, width: 536, height: 200),
                            cornerSize: CGSize(width: 62, height: 62))

        // 两根天线
        path.move(to: CGPoint(x: 356, y: 503))
        path.addLine(to: CGPoint(x: 306, y: 359))
        path.move(to: CGPoint(x: 668, y: 503))
        path.addLine(to: CGPoint(x: 718, y: 359))

        // 主弧 + 小弧
        RouterGeometry.addArc(&path,
                              from: CGPoint(x: 386, y: 383),
                              to: CGPoint(x: 638, y: 383),
                              radius: 200)
        RouterGeometry.addArc(&path,
                              from: CGPoint(x: 448, y: 454),
                              to: CGPoint(x: 576, y: 454),
                              radius: 96)

        // 前面板的一道分缝
        if showsDetails {
            path.move(to: CGPoint(x: 300, y: 624))
            path.addLine(to: CGPoint(x: 470, y: 624))
        }

        return path.applying(RouterGeometry.transform(in: rect))
    }
}

/// 指示灯：图标里是实心点，不能并进描边路径（描边会画成一圈粗环）。
private struct RouterGlyphLamp: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 669, y: 609, width: 30, height: 30))
        return path.applying(RouterGeometry.transform(in: rect))
    }
}
