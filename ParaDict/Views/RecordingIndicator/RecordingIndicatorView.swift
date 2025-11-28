import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var dictationManager: DictationManager
    @EnvironmentObject var windowManager: RecordingIndicatorWindowManager

    private var backgroundView: some View {
        ZStack {
            Color.black.opacity(0.9)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.95),
                    Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.05)
        }
        .clipShape(Capsule())
    }

    private var statusView: some View {
        RecordingStatusDisplay(
            currentState: dictationManager.state,
            recordingService: dictationManager.recordingService
        )
    }

    private var contentLayout: some View {
        HStack(spacing: 0) {
            Spacer()
            statusView
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 16)
    }

    private var recorderCapsule: some View {
        Capsule()
            .fill(.clear)
            .background(backgroundView)
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            }
            .overlay {
                contentLayout
            }
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                recorderCapsule
            }
        }
    }
}

struct RecordingStatusDisplay: View {
    let currentState: DictationState
    @ObservedObject var recordingService: RecordingService

    private let matrixGreen = Color(red: 0, green: 1, blue: 0.2)
    private let matrixBlue = Color(red: 0.3, green: 0.6, blue: 1.0)
    private let matrixYellow = Color(red: 1.0, green: 0.8, blue: 0.2)

    @State private var processingStartTime: Date = Date()

    var body: some View {
        Group {
            if currentState == .enhancing {
                DotMatrixProgressIndicator(color: matrixYellow, startTime: processingStartTime)
            } else if currentState == .transcribing {
                DotMatrixProgressIndicator(color: matrixBlue, startTime: processingStartTime)
            } else if currentState == .recording {
                DotMatrixVisualizer(
                    recordingService: recordingService,
                    color: Color(red: 0, green: 1, blue: 0.2),
                    isActive: true
                )
            } else {
                StaticWaveform(color: .white)
            }
        }
        .animation(nil, value: currentState)
        .onChange(of: currentState) { oldState, newState in
            // Reset timer when transitioning from recording to transcribing
            if oldState == .recording && newState == .transcribing {
                processingStartTime = Date()
            }
        }
    }
}
