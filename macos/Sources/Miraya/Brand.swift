import SwiftUI

/// Code-native artwork keeps every asset crisp on Retina and TV-sized screens.
enum MirayaTheme {
    static let midnight = Color(red: 0.025, green: 0.045, blue: 0.085)
    static let panel = Color(red: 0.043, green: 0.075, blue: 0.13)
    static let cyan = Color(red: 0, green: 0.90, blue: 1)
    static let blue = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let soft = Color(red: 0.65, green: 0.78, blue: 1)
    static let border = Color(red: 0.15, green: 0.27, blue: 0.42)
    static let flow = LinearGradient(colors: [cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct MirayaWordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Canvas { context, size in
                var m = Path()
                m.move(to: CGPoint(x: 4, y: 40)); m.addLine(to: CGPoint(x: 4, y: 5))
                m.addLine(to: CGPoint(x: 25, y: 26)); m.addLine(to: CGPoint(x: 46, y: 5)); m.addLine(to: CGPoint(x: 46, y: 40))
                context.stroke(m, with: .linearGradient(Gradient(colors: [.white, MirayaTheme.cyan, MirayaTheme.blue]), startPoint: .zero, endPoint: CGPoint(x: 50,y: 45)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }.frame(width: 51, height: 44).alignmentGuide(.firstTextBaseline) { _ in 40 }
            Text("iraya").font(.system(size: 48, weight: .semibold, design: .rounded)).tracking(-2).foregroundStyle(.white)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Miraya")
    }
}

struct ConnectionArtwork: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse().fill(MirayaTheme.blue.opacity(0.18)).blur(radius: 18).frame(width: w*0.9, height: h*0.7).offset(y: 16)
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [MirayaTheme.blue.opacity(0.55), MirayaTheme.midnight], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(MirayaTheme.cyan, lineWidth: 1.5))
                    .frame(width: w*0.47, height: h*0.70).shadow(color: MirayaTheme.cyan.opacity(0.45), radius: 8).position(x: w*0.72, y: h*0.41)
                RoundedRectangle(cornerRadius: 3).fill(MirayaTheme.soft.opacity(0.8)).frame(width: w*0.20,height: 3).position(x: w*0.72,y: h*0.83)
                RoundedRectangle(cornerRadius: 5).fill(LinearGradient(colors: [MirayaTheme.soft.opacity(0.6), MirayaTheme.blue.opacity(0.4), MirayaTheme.midnight], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(MirayaTheme.soft,lineWidth: 1.2))
                    .frame(width: w*0.32,height: h*0.43).position(x: w*0.20,y: h*0.65)
                RoundedRectangle(cornerRadius: 2).fill(MirayaTheme.cyan).frame(width: w*0.38,height: 3).position(x: w*0.20,y: h*0.90)
                Canvas { context, size in
                    var wave = Path(); wave.move(to: CGPoint(x: size.width*0.12, y: size.height*0.80))
                    wave.addCurve(to: CGPoint(x:size.width*0.92,y:size.height*0.65), control1:CGPoint(x:size.width*0.52,y:size.height*0.94), control2:CGPoint(x:size.width*0.42,y:size.height*0.10))
                    context.addFilter(.shadow(color: MirayaTheme.cyan.opacity(0.8),radius:5))
                    context.stroke(wave,with:.color(MirayaTheme.cyan),lineWidth:3)
                    context.stroke(wave.offsetBy(dx:0,dy:5),with:.color(.white.opacity(0.5)),lineWidth:1)
                }
            }
        }.accessibilityHidden(true)
    }
}
