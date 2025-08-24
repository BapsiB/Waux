import SwiftUI

struct WaveformView: View {
    let waveformData: [Double]
    let progress: Double // 0.0 - 1.0
    let markers: [TimeMarker]
    let durationMs: Int
    var activeColor: Color = .blue
    var inactiveColor: Color = .gray.opacity(0.5)
    var progressLineColor: Color = .red
    var markerColor: Color = .blue
    var lineWidth: CGFloat = 2.0

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !waveformData.isEmpty else { return }

                let centerY = size.height / 2.0
                let maxAmplitude = size.height * 0.4

                // Downsample to about half the pixel width like the Flutter code
                let targetPoints = max(1, Int(size.width / 2.0))
                let data = downsample(waveformData, to: targetPoints)
                if data.isEmpty { return }

                let spacing = size.width / CGFloat(max(1, data.count - 1))
                let clampedProgress = max(0.0, min(1.0, progress))
                let splitIndex = Int((clampedProgress * Double(data.count)).rounded(.down))

                var playedPath = Path()
                var unplayedPath = Path()

                for i in 0..<data.count {
                    let x = CGFloat(i) * spacing
                    let amplitude = CGFloat(max(0.0, min(1.0, data[i]))) * maxAmplitude
                    let topY = centerY - amplitude
                    let bottomY = centerY + amplitude

                    if i < splitIndex {
                        playedPath.move(to: CGPoint(x: x, y: topY))
                        playedPath.addLine(to: CGPoint(x: x, y: bottomY))
                    } else {
                        unplayedPath.move(to: CGPoint(x: x, y: topY))
                        unplayedPath.addLine(to: CGPoint(x: x, y: bottomY))
                    }
                }

                context.stroke(playedPath, with: .color(activeColor), lineWidth: lineWidth)
                context.stroke(unplayedPath, with: .color(inactiveColor), lineWidth: lineWidth)

                // Draw markers (full-height bar + small label near the top, to the right of the bar)
                if durationMs > 0 {
                    let labelFont = Font.system(size: 11, weight: .regular)
                    let paddingH: CGFloat = 6
                    let paddingV: CGFloat = 3
                    let elementSpacing: CGFloat = 4
                    let labelTop: CGFloat = 2

                    for marker in markers {
                        let ratio = max(0.0, min(1.0, Double(marker.time) / Double(durationMs)))
                        let x = CGFloat(ratio) * size.width

                        // Marker bar
                        var bar = Path()
                        bar.move(to: CGPoint(x: x, y: 0))
                        bar.addLine(to: CGPoint(x: x, y: size.height))
                        let color = marker.color ?? markerColor
                        context.stroke(bar, with: .color(color), lineWidth: 2)

                        // Label background rect positioned to the right of the bar
                        let text = Text(marker.label)
                            .font(labelFont)
                        let resolved = context.resolve(text)
                        let textSize = resolved.measure(in: CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
                        let bgWidth = min(100, textSize.width) + paddingH * 2
                        let bgHeight = textSize.height + paddingV * 2
                        let bgRect = CGRect(
                            x: min(max(0, x + elementSpacing), size.width - bgWidth),
                            y: labelTop,
                            width: bgWidth,
                            height: bgHeight
                        )

                        let rounded = RoundedRectangle(cornerRadius: 4).path(in: bgRect)
                        context.fill(rounded, with: .color(color.opacity(0.85)))

                        // Draw text centered vertically in bg rect
                        let textPoint = CGPoint(
                            x: bgRect.minX + paddingH,
                            y: bgRect.midY
                        )
                        context.draw(text, at: textPoint, anchor: .leading)
                    }
                }

                // Progress line (on top)
                let progressX = CGFloat(clampedProgress) * size.width
                var progressPath = Path()
                progressPath.move(to: CGPoint(x: progressX, y: 0))
                progressPath.addLine(to: CGPoint(x: progressX, y: size.height))
                context.stroke(progressPath, with: .color(progressLineColor), lineWidth: 2)
            }
        }
    }

    private func downsample(_ source: [Double], to targetPoints: Int) -> [Double] {
        guard !source.isEmpty else { return [0.0] }
        guard targetPoints > 0 else { return [0.0] }
        if source.count <= targetPoints { return source }

        var result = Array(repeating: 0.0, count: targetPoints)
        let ratio = Double(source.count) / Double(targetPoints)
        for i in 0..<targetPoints {
            let start = Int(Double(i) * ratio)
            let end = min(Int(Double(i + 1) * ratio), source.count)
            if start >= end {
                result[i] = abs(source[min(start, source.count - 1)])
                continue
            }
            var maxValue = 0.0
            var j = start
            while j < end { // tight loop
                let v = abs(source[j])
                if v > maxValue { maxValue = v }
                j += 1
            }
            result[i] = maxValue
        }
        return result
    }
}


