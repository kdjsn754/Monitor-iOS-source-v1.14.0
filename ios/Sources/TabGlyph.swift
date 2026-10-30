import Foundation
import SwiftUI

/// 底部导航栏的三枚图标。
///
/// 画法向系统 App 的底栏看齐：24×24 设计框、1.7 的线宽、圆头圆角，
/// 未选中画空心、选中换实心（实心不是把空心加粗，而是另一套闭合路径）。
/// 图案沿用原来的三枚——网格 / 盾牌 / 齿轮——只是重新描了一遍，
/// 让它们和别家 App 底栏的图标一样「笔画一致、边角圆润、选中变实」。
enum TabGlyphKind {
    case overview
    case proxy
    case settings
}

struct TabGlyph: View {
    let kind: TabGlyphKind
    var filled: Bool = false
    /// 线宽（设计框 24 单位下的值，实际按尺寸等比缩放）
    var lineWidth: CGFloat = 1.7

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 24
            let shape = Self.path(kind, scale: scale)
            if filled {
                // even-odd：齿轮中间的孔是「挖」出来的，不是叠一个白圆（深色模式下会穿帮）
                shape.fill(style: FillStyle(eoFill: true))
            } else {
                shape.stroke(style: StrokeStyle(lineWidth: lineWidth * max(scale, 0.01),
                                                lineCap: .round,
                                                lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - 路径

    private static func path(_ kind: TabGlyphKind, scale: CGFloat) -> Path {
        var p: Path
        switch kind {
        case .overview: p = overviewPath()
        case .proxy: p = proxyPath()
        case .settings: p = settingsPath()
        }
        return p.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    /// 概览：2×2 圆角方块。
    private static func overviewPath() -> Path {
        var p = Path()
        let side: CGFloat = 9.3
        let gap: CGFloat = 2.4
        let pitch = side + gap
        let corner: CGFloat = 2.7
        for sx in [-1, 1] {
            for sy in [-1, 1] {
                let cx = 12 + CGFloat(sx) * pitch / 2
                let cy = 12 + CGFloat(sy) * pitch / 2
                p.addRoundedRect(
                    in: CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side),
                    cornerSize: CGSize(width: corner, height: corner),
                    style: .continuous
                )
            }
        }
        return p
    }

    /// 代理：盾牌。上边两角圆角、两侧直下、底部收成一个圆头的尖。
    private static func proxyPath() -> Path {
        var p = Path()
        let half: CGFloat = 9.15      // 半宽
        let top: CGFloat = 2.0
        let tip: CGFloat = 22.2
        let shoulder: CGFloat = 13.2  // 直边结束、开始收尖的位置
        let r: CGFloat = 4.1          // 上圆角

        p.move(to: CGPoint(x: 12 - half, y: top + r))
        // 左上圆角：180° → 270°（注意 Path.addArc 在翻转坐标系里方向是反的，
        // 所以这里一律用折线自己描，不再用 addArc）
        addArc(&p, center: CGPoint(x: 12 - half + r, y: top + r), radius: r, from: 180, to: 270, moveFirst: false)
        p.addLine(to: CGPoint(x: 12 + half - r, y: top))
        addArc(&p, center: CGPoint(x: 12 + half - r, y: top + r), radius: r, from: 270, to: 360, moveFirst: false)
        p.addLine(to: CGPoint(x: 12 + half, y: shoulder))
        p.addCurve(to: CGPoint(x: 12, y: tip),
                   control1: CGPoint(x: 12 + half, y: shoulder + 4.3),
                   control2: CGPoint(x: 12 + half * 0.52, y: tip - 1.5))
        p.addCurve(to: CGPoint(x: 12 - half, y: shoulder),
                   control1: CGPoint(x: 12 - half * 0.52, y: tip - 1.5),
                   control2: CGPoint(x: 12 - half, y: shoulder + 4.3))
        p.closeSubpath()
        return p
    }

    /// 设置：8 齿齿轮，中间一个圆孔。
    private static func settingsPath() -> Path {
        var p = Path()
        let teeth = 8
        let step: CGFloat = 360 / 8
        let rOut: CGFloat = 10.4
        let rRoot: CGFloat = 7.9
        let head: CGFloat = 11.5   // 齿顶半角
        let base: CGFloat = 17.5   // 齿根半角
        let hole: CGFloat = 3.9

        for i in 0..<teeth {
            let a = CGFloat(i) * step - 90
            let pts = [
                point(rRoot, a - base), point(rOut, a - head),
                point(rOut, a + head), point(rRoot, a + base)
            ]
            if i == 0 {
                p.move(to: pts[0])
            } else {
                p.addLine(to: pts[0])
            }
            for q in pts.dropFirst() { p.addLine(to: q) }
            // 谷底：沿齿根圆走到下一个齿（最后一个齿也要走，否则收尾处会缺一小段弧、
            // 变成一条直弦，在齿根上留个平角）
            addArc(&p, center: CGPoint(x: 12, y: 12), radius: rRoot,
                   from: a + base, to: a + step - base, moveFirst: false, steps: 8)
        }
        p.closeSubpath()

        // 中心孔：单独一条子路径，实心时靠 even-odd 挖空，空心时被描成一圈
        p.addEllipse(in: CGRect(x: 12 - hole, y: 12 - hole, width: hole * 2, height: hole * 2))
        return p
    }

    // MARK: - 小工具

    private static func point(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
        let rad = deg * .pi / 180
        return CGPoint(x: 12 + r * cos(rad), y: 12 + r * sin(rad))
    }

    /// 用折线描圆弧。SwiftUI 里 `Path.addArc` 的顺/逆时针在翻转坐标系下会反着走，
    /// 1.28.4 已经被它画成过「一只眼睛」，所以这里坚持自己采样。
    private static func addArc(_ p: inout Path,
                               center: CGPoint,
                               radius: CGFloat,
                               from a0: CGFloat,
                               to a1: CGFloat,
                               moveFirst: Bool,
                               steps: Int = 16) {
        for i in 0...steps {
            let deg = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
            let rad = deg * .pi / 180
            let q = CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
            if i == 0 && moveFirst {
                p.move(to: q)
            } else {
                p.addLine(to: q)
            }
        }
    }
}
