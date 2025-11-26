import SwiftUI

struct WaveformVisualizer: View {
    @ObservedObject var recorder: Recorder
    let color: Color
    let isActive: Bool

    private let pointCount = 48
    private let waveHeight: CGFloat = 28
    private let waveWidth: CGFloat = 80

    @State private var phases: [Double]
    @State private var amplitudes: [Double]
    @State private var targetAmplitude: Double = 0

    init(recorder: Recorder, color: Color, isActive: Bool) {
        self.recorder = recorder
        self.color = color
        self.isActive = isActive

        // Initialize with random phases for organic look
        _phases = State(initialValue: (0..<3).map { _ in Double.random(in: 0...Double.pi * 2) })
        _amplitudes = State(initialValue: [0.3, 0.2, 0.15])
    }

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2

            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))

            for i in 0..<pointCount {
                let x = (CGFloat(i) / CGFloat(pointCount - 1)) * size.width
                let normalizedX = Double(i) / Double(pointCount - 1)

                // Combine multiple sine waves for organic movement
                var y = midY
                for j in 0..<phases.count {
                    let frequency = Double(j + 1) * 2.0
                    let wave = sin(normalizedX * Double.pi * frequency + phases[j])
                    y += CGFloat(wave * amplitudes[j] * targetAmplitude) * (waveHeight / 2)
                }

                // Taper at edges
                let edgeFactor = sin(normalizedX * Double.pi)
                y = midY + (y - midY) * edgeFactor

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 2.5)
        }
        .frame(width: waveWidth, height: waveHeight)
        .onChange(of: recorder.audioMeter) { _, newValue in
            if isActive {
                updateWaveform(with: newValue.averagePower)
            }
        }
        .onChange(of: isActive) { _, newValue in
            if !newValue {
                resetWaveform()
            }
        }
        .onAppear {
            startPhaseAnimation()
        }
    }

    private func updateWaveform(with power: Double) {
        let normalizedPower = max(0, min(1, power))

        // Aggressive amplitude mapping for more reactivity
        // Apply curve to make quieter sounds more visible
        let boostedPower = pow(normalizedPower, 0.6) * 2.5

        withAnimation(.easeOut(duration: 0.05)) {
            targetAmplitude = max(0.2, boostedPower)
        }
    }

    private func resetWaveform() {
        withAnimation(.easeOut(duration: 0.2)) {
            targetAmplitude = 0
        }
    }

    private func startPhaseAnimation() {
        // Continuously animate phase shifts for flowing motion
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            Task { @MainActor in
                for i in 0..<phases.count {
                    phases[i] += 0.25 * Double(i + 1)
                }
            }
        }
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
