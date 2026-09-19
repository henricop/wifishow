import AppKit
import CoreGraphics

// Gera o icone do WifiShow seguindo o gabarito de app macOS:
// canvas 1024, conteudo 824x824 centrado, silhueta em superelipse (squircle).

let CANVAS: CGFloat = 1024
let INSET: CGFloat = 100                    // margem do gabarito Apple
let SIDE: CGFloat = CANVAS - INSET * 2      // 824

/// Squircle da Apple: superelipse |x/a|^n + |y/b|^n = 1, com n ~ 5.
func squircle(rect: CGRect, n: Double = 5, steps: Int = 720) -> CGPath {
    let p = CGMutablePath()
    let a = Double(rect.width / 2), b = Double(rect.height / 2)
    let cx = Double(rect.midX), cy = Double(rect.midY)
    for i in 0...steps {
        let t = 2 * Double.pi * Double(i) / Double(steps)
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

func drawIcon(into ctx: CGContext) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let content = CGRect(x: INSET, y: INSET, width: SIDE, height: SIDE)
    let shape = squircle(rect: content)

    // --- Fundo: gradiente azul -> ciano, na diagonal
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: space,
                          colors: [rgb(28, 66, 224), rgb(10, 132, 255), rgb(24, 205, 208)] as CFArray,
                          locations: [0.0, 0.52, 1.0])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: content.minX, y: content.maxY),
                           end:   CGPoint(x: content.maxX, y: content.minY),
                           options: [])

    // --- Curvas espectrais ao fundo: a assinatura do analyzer
    // Parabolas sobrepostas, iguais as que o app desenha.
    let curves: [(center: CGFloat, width: CGFloat, peak: CGFloat, alpha: CGFloat)] = [
        (0.26, 0.44, 0.20, 0.16),
        (0.52, 0.56, 0.26, 0.21),
        (0.78, 0.40, 0.17, 0.14),
    ]
    // Base abaixo da area de conteudo: o clip do squircle corta naturalmente,
    // sem deixar uma aresta reta atravessando o icone.
    let base = content.minY - SIDE * 0.05
    for c in curves {
        let cx = content.minX + SIDE * c.center
        let half = SIDE * c.width / 2
        let peak = SIDE * c.peak
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx - half, y: base))
        for i in 0...64 {
            let t = CGFloat(i) / 64
            let x = cx - half + t * half * 2
            let d = (x - cx) / half
            let y = base + peak * (1 - d * d)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: cx + half, y: base))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 1, alpha: c.alpha))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // --- Simbolo Wi-Fi: tres arcos + ponto
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let originX = CANVAS / 2
    let originY = INSET + SIDE * 0.30
    let lw = SIDE * 0.082
    ctx.setLineCap(.round)
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))

    // Sombra suave para descolar do fundo
    ctx.setShadow(offset: CGSize(width: 0, height: -SIDE * 0.012),
                  blur: SIDE * 0.05,
                  color: rgb(0, 20, 70, 0.30))

    for r in [SIDE * 0.20, SIDE * 0.33, SIDE * 0.46] {
        ctx.addArc(center: CGPoint(x: originX, y: originY),
                   radius: r,
                   startAngle: .pi / 4.55,
                   endAngle: .pi - .pi / 4.55,
                   clockwise: false)
        ctx.strokePath()
    }

    ctx.addArc(center: CGPoint(x: originX, y: originY),
               radius: lw * 0.60, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // --- Brilho superior sutil (volume), no padrao dos icones do sistema
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss,
                           start: CGPoint(x: content.midX, y: content.maxY),
                           end:   CGPoint(x: content.midX, y: content.midY + SIDE * 0.10),
                           options: [])
    ctx.restoreGState()

    // --- Borda interna para definir a silhueta em fundos claros
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.10))
    ctx.setLineWidth(SIDE * 0.006)
    ctx.strokePath()
    ctx.restoreGState()
}

func render(size: CGFloat) -> CGImage {
    let scale = size / CANVAS
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(into: ctx)
    return ctx.makeImage()!
}

func write(_ img: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: img.width, height: img.height)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// --- Saida
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(out)/WifiShow.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let variants: [(px: CGFloat, name: String)] = [
    (16, "icon_16x16.png"),     (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),     (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),  (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),  (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),  (1024, "icon_512x512@2x.png"),
]
for v in variants { write(render(size: v.px), to: "\(iconset)/\(v.name)") }
write(render(size: 1024), to: "\(out)/icon-preview.png")
print("iconset gerado em \(iconset)")
