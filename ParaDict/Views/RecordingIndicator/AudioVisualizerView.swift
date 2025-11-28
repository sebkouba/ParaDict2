import SwiftUI

// MARK: - Style 1: Classic Bars (like react-voice-visualizer)
struct BarVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    private let barCount = 20
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90

    @State private var barHeights: [Double] = Array(repeating: 0.1, count: 20)

    var body: some View {
        Canvas { context, size in
            let barWidth = size.width / CGFloat(barCount) * 0.7
            let gap = size.width / CGFloat(barCount) * 0.3

            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + gap) + gap / 2
                let height = CGFloat(barHeights[i]) * size.height
                let y = (size.height - height) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                context.fill(RoundedRectangle(cornerRadius: barWidth / 2).path(in: rect), with: .color(color))
            }
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recordingService.audioMeter) { _, newValue in
            if isActive {
                updateBars(with: newValue.averagePower)
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                withAnimation(.easeOut(duration: 0.2)) {
                    barHeights = Array(repeating: 0.1, count: barCount)
                }
            }
        }
    }

    private func updateBars(with power: Double) {
        let normalizedPower = pow(max(0, min(1, power)), 0.5)
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 12)) {
            for i in 0..<barCount {
                // Create variation across bars - center bars taller
                let centerFactor = 1.0 - abs(Double(i) / Double(barCount - 1) - 0.5) * 1.2
                let randomVariation = Double.random(in: 0.7...1.0)
                barHeights[i] = max(0.08, normalizedPower * centerFactor * randomVariation * 0.9)
            }
        }
    }
}

// MARK: - Style 2: Mirrored Bars (symmetric up/down)
struct MirroredBarVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    private let barCount = 24
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90

    @State private var barHeights: [Double] = Array(repeating: 0.05, count: 24)

    var body: some View {
        Canvas { context, size in
            let barWidth = size.width / CGFloat(barCount) * 0.6
            let gap = size.width / CGFloat(barCount) * 0.4
            let midY = size.height / 2

            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + gap) + gap / 2
                let halfHeight = CGFloat(barHeights[i]) * size.height / 2

                // Top bar (going up from center)
                let topRect = CGRect(x: x, y: midY - halfHeight, width: barWidth, height: halfHeight)
                context.fill(RoundedRectangle(cornerRadius: barWidth / 2).path(in: topRect), with: .color(color))

                // Bottom bar (going down from center)
                let bottomRect = CGRect(x: x, y: midY, width: barWidth, height: halfHeight)
                context.fill(RoundedRectangle(cornerRadius: barWidth / 2).path(in: bottomRect), with: .color(color))
            }
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recordingService.audioMeter) { _, newValue in
            if isActive {
                updateBars(with: newValue.averagePower)
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                withAnimation(.easeOut(duration: 0.2)) {
                    barHeights = Array(repeating: 0.05, count: barCount)
                }
            }
        }
    }

    private func updateBars(with power: Double) {
        let normalizedPower = pow(max(0, min(1, power)), 0.45)
        withAnimation(.interpolatingSpring(stiffness: 350, damping: 14)) {
            for i in 0..<barCount {
                let centerFactor = 1.0 - abs(Double(i) / Double(barCount - 1) - 0.5) * 1.5
                let variation = Double.random(in: 0.6...1.0)
                barHeights[i] = max(0.05, normalizedPower * centerFactor * variation * 0.95)
            }
        }
    }
}

// MARK: - Style 3: Smooth Wave Bars (bars with smooth height transition)
struct SmoothWaveBarVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    private let barCount = 16
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90

    @State private var audioLevel: Double = 0.0

    var body: some View {
        Canvas { context, size in
            let barWidth = size.width / CGFloat(barCount) * 0.65
            let gap = size.width / CGFloat(barCount) * 0.35
            let midY = size.height / 2

            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + gap) + gap / 2
                let normalizedX = Double(i) / Double(barCount - 1)

                // Smooth sine-based height distribution
                let envelope = sin(normalizedX * Double.pi)
                let wavePhase = sin(normalizedX * Double.pi * 2.5)
                let height = (0.3 + envelope * 0.7 + wavePhase * 0.2) * audioLevel * size.height * 0.9

                let halfHeight = CGFloat(height) / 2
                let rect = CGRect(x: x, y: midY - halfHeight, width: barWidth, height: max(2, CGFloat(height)))
                context.fill(RoundedRectangle(cornerRadius: barWidth / 2).path(in: rect), with: .color(color))
            }
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recordingService.audioMeter) { _, newValue in
            if isActive {
                let power = pow(max(0, min(1, newValue.averagePower)), 0.5)
                withAnimation(.interpolatingSpring(stiffness: 400, damping: 15)) {
                    audioLevel = max(0.1, power)
                }
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                withAnimation(.easeOut(duration: 0.2)) {
                    audioLevel = 0.0
                }
            }
        }
    }
}

// MARK: - Style 4: Layered Mesh Waves (original style)
struct MeshWaveVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    private let pointCount = 60
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90
    private let lineCount = 12

    @State private var displayedLevel: Double = 0.0

    var body: some View {
        Canvas { context, size in
            drawWaves(context: context, size: size)
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recordingService.audioMeter) { _, newValue in
            if isActive {
                let power = pow(max(0, min(1, newValue.averagePower)), 0.4) * 1.2
                withAnimation(.interpolatingSpring(stiffness: 400, damping: 15)) {
                    displayedLevel = min(1.0, power)
                }
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                withAnimation(.easeOut(duration: 0.2)) {
                    displayedLevel = 0
                }
            }
        }
    }

    private func drawWaves(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2
        let maxAmplitude = (size.height / 2) - 2

        for lineIndex in 0..<lineCount {
            let lineOffset = Double(lineIndex) / Double(lineCount)
            let opacity = 0.15 + (1.0 - abs(lineOffset - 0.5) * 2) * 0.3

            var path = Path()
            for i in 0..<pointCount {
                let progress = Double(i) / Double(pointCount - 1)
                let x = CGFloat(progress) * size.width
                let envelope = sin(progress * Double.pi)
                let wave = sin(progress * Double.pi * 3 + lineOffset * Double.pi) * envelope * displayedLevel
                let y = midY + CGFloat(wave * Double(maxAmplitude))

                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1.2)
        }
    }
}

// MARK: - Style 5: Dot Matrix
struct DotMatrixVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    private let columns = 12
    private let rows = 5
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90

    @State private var audioLevel: Double = 0.0

    var body: some View {
        Canvas { context, size in
            let dotSize = min(size.width / CGFloat(columns), size.height / CGFloat(rows)) * 0.6
            let xSpacing = size.width / CGFloat(columns)
            let ySpacing = size.height / CGFloat(rows)
            let midRow = Double(rows - 1) / 2.0

            for col in 0..<columns {
                let normalizedX = Double(col) / Double(columns - 1)
                let envelope = sin(normalizedX * Double.pi)
                let activeRows = Int(ceil(envelope * audioLevel * Double(rows)))

                for row in 0..<rows {
                    let distanceFromCenter = abs(Double(row) - midRow)
                    let isActive = distanceFromCenter < Double(activeRows) / 2.0

                    let x = CGFloat(col) * xSpacing + xSpacing / 2
                    let y = CGFloat(row) * ySpacing + ySpacing / 2
                    let opacity = isActive ? (0.5 + envelope * 0.5) : 0.1

                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Circle().path(in: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recordingService.audioMeter) { _, newValue in
            if isActive {
                let rawPower = max(0, min(1, newValue.averagePower))
                // Noise floor - ignore quiet sounds below threshold
                let threshold: Double = 0.25
                let adjusted = max(0, (rawPower - threshold) / (1.0 - threshold))
                let power = pow(adjusted, 0.5)
                // Very stiff, high damping = fast response, no overshoot
                withAnimation(.interpolatingSpring(stiffness: 800, damping: 30)) {
                    audioLevel = power
                }
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                withAnimation(.easeOut(duration: 0.15)) {
                    audioLevel = 0.0
                }
            }
        }
    }
}

// MARK: - Dot Matrix Progress Indicator (spreading from center)
struct DotMatrixProgressIndicator: View {
    let color: Color
    let startTime: Date

    private let columns = 12
    private let rows = 5
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90
    private let cycleTime: Double = 0.5

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startTime)
            let cycleElapsed = elapsed.truncatingRemainder(dividingBy: cycleTime * 2)
            let progress = cycleElapsed < cycleTime
                ? cycleElapsed / cycleTime
                : 1.0 - ((cycleElapsed - cycleTime) / cycleTime)

            Canvas { context, size in
                drawDots(context: context, size: size, progress: progress)
            }
        }
        .frame(width: waveWidth, height: waveHeight)
    }

    private func drawDots(context: GraphicsContext, size: CGSize, progress: Double) {
        let dotSize = min(size.width / CGFloat(columns), size.height / CGFloat(rows)) * 0.6
        let xSpacing = size.width / CGFloat(columns)
        let ySpacing = size.height / CGFloat(rows)
        let midCol = Double(columns - 1) / 2.0
        let midRow = Double(rows - 1) / 2.0
        let maxDistance = sqrt(midCol * midCol + midRow * midRow)

        for col in 0..<columns {
            for row in 0..<rows {
                let distanceFromCenterX = abs(Double(col) - midCol)
                let distanceFromCenterY = abs(Double(row) - midRow)
                let distance = sqrt(distanceFromCenterX * distanceFromCenterX + distanceFromCenterY * distanceFromCenterY)
                let normalizedDistance = distance / maxDistance

                let isActive = normalizedDistance <= progress

                let x = CGFloat(col) * xSpacing + xSpacing / 2
                let y = CGFloat(row) * ySpacing + ySpacing / 2
                let opacity = isActive ? 0.8 : 0.1

                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                context.fill(Circle().path(in: rect), with: .color(color.opacity(opacity)))
            }
        }
    }
}

// MARK: - Test View with all 5 styles
struct VisualizerTestView: View {
    @ObservedObject var recordingService: RecordingService
    let isActive: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                BarVisualizer(recordingService: recordingService, color: color, isActive: isActive)
                Text("1").font(.caption2).foregroundColor(.white.opacity(0.6))
            }
            VStack(spacing: 4) {
                MirroredBarVisualizer(recordingService: recordingService, color: color, isActive: isActive)
                Text("2").font(.caption2).foregroundColor(.white.opacity(0.6))
            }
            VStack(spacing: 4) {
                SmoothWaveBarVisualizer(recordingService: recordingService, color: color, isActive: isActive)
                Text("3").font(.caption2).foregroundColor(.white.opacity(0.6))
            }
            VStack(spacing: 4) {
                MeshWaveVisualizer(recordingService: recordingService, color: color, isActive: isActive)
                Text("4").font(.caption2).foregroundColor(.white.opacity(0.6))
            }
            VStack(spacing: 4) {
                DotMatrixVisualizer(recordingService: recordingService, color: color, isActive: isActive)
                Text("5").font(.caption2).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Main Waveform (uses Style 2 by default for now)
struct WaveformVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    var body: some View {
        MirroredBarVisualizer(recordingService: recordingService, color: color, isActive: isActive)
    }
}

struct StaticWaveform: View {
    let color: Color
    private let waveWidth: CGFloat = 80
    private let waveHeight: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2

            // Draw a simple flat line
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            path.addLine(to: CGPoint(x: size.width, y: midY))

            context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 2)
        }
        .frame(width: waveWidth, height: waveHeight)
    }
}

struct ProgressAnimation: View {
    @State private var phase: CGFloat = 0
    let color: Color

    private let waveWidth: CGFloat = 80
    private let waveHeight: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2

            var path = Path()

            for i in 0..<48 {
                let x = (CGFloat(i) / 47) * size.width
                let normalizedX = Double(i) / 47

                // Gentle pulsing wave
                let wave = sin(normalizedX * Double.pi * 4 + Double(phase))
                let edgeFactor = sin(normalizedX * Double.pi)
                let y = midY + CGFloat(wave * 0.3) * (waveHeight / 2) * edgeFactor

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 2)
        }
        .frame(width: waveWidth, height: waveHeight)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = Double.pi * 2
            }
        }
    }
}
