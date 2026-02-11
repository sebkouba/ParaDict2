import SwiftUI

/// SwiftUI view for the streaming transcription preview overlay.
/// Text is grey while streaming (partial), turns solid white when recording stops (finalized).
struct TranscriptionPreviewView: View {
    @ObservedObject var streamingService = StreamingTranscriptionService.shared

    private var displayText: String {
        streamingService.partialTranscription.isEmpty ? "Listening..." : streamingService.partialTranscription
    }

    private var isListening: Bool {
        streamingService.partialTranscription.isEmpty
    }

    /// Grey while actively streaming, solid white when finalized (recording stopped)
    private var textColor: Color {
        if isListening {
            return .white.opacity(0.4)
        }
        return streamingService.isStreaming ? .white.opacity(0.5) : .white.opacity(0.95)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(displayText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .id("bottom")
            }
            .onChange(of: streamingService.partialTranscription) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(
            ZStack {
                Color.black.opacity(0.85)
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .opacity(0.05)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}
