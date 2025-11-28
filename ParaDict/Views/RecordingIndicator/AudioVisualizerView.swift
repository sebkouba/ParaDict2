import SwiftUI

struct WaveformVisualizer: View {
    @ObservedObject var recordingService: RecordingService
    let color: Color
    let isActive: Bool

    private let pointCount = 60
    private let waveHeight: CGFloat = 32
    private let waveWidth: CGFloat = 90
    private let lineCount = 12

    @State private var time: Double = 0
    @State private var audioLevel: Double = 0.3
    @State private var timer: Timer?

    var body: some View {
        Canvas { context, size in
            drawWaves(context: context, size: size)
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recordingService.audioMeter) { _, newValue in
            if isActive {
                updateWaveform(with: newValue.averagePower)
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onAppear {
            if isActive {
                startAnimation()
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }

    private func startAnimation() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            Task { @MainActor in
                time += 0.06
            }
        }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.3)) {
            audioLevel = 0.1
        }
    }

    private func updateWaveform(with power: Double) {
        let normalizedPower = max(0, min(1, power))
        let boostedPower = pow(normalizedPower, 0.5) * 2.0
        withAnimation(.easeOut(duration: 0.08)) {
            audioLevel = max(0.3, min(1.5, boostedPower))
        }
    }

    private func drawWaves(context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2

        for lineIndex in 0..<lineCount {
            let lineOffset = Double(lineIndex) / Double(lineCount)
            let centerDistance = abs(lineOffset - 0.5) * 2
            let opacity = 0.15 + (1.0 - centerDistance) * 0.25

            var path = Path()

            for i in 0..<pointCount {
                let progress = Double(i) / Double(pointCount - 1)
                let x = CGFloat(progress) * size.width

                let y = calculateWaveY(
                    normalizedX: progress,
                    lineOffset: lineOffset,
                    midY: midY
                )

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1.2)
        }
    }

    private func calculateWaveY(normalizedX: Double, lineOffset: Double, midY: CGFloat) -> CGFloat {
        let envelope = sin(normalizedX * Double.pi)

        let phase1 = normalizedX * Double.pi * 3 + time * 2 + lineOffset * Double.pi
        let phase2 = normalizedX * Double.pi * 5 + time * 1.3 + lineOffset * Double.pi * 0.7
        let phase3 = normalizedX * Double.pi * 2 + time * 0.8 + lineOffset * Double.pi * 1.3

        let freq1 = sin(phase1)
        let freq2 = sin(phase2) * 0.5
        let freq3 = sin(phase3) * 0.3

        let ampPhase = normalizedX * Double.pi * 2 + time * 0.5 + lineOffset * 3
        let ampMod = 0.5 + 0.5 * sin(ampPhase)

        let wave = (freq1 + freq2 + freq3) * envelope * ampMod * audioLevel
        return midY + CGFloat(wave) * (waveHeight / 2)
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
