import SwiftUI

struct CorrectionView: View {
    let originalTranscription: String
    let llmOutput: String
    let onSubmit: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var correctedText: String
    @State private var explanation: String = ""
    @FocusState private var isCorrectionFocused: Bool

    /// Whether LLM enhancement was used (transcription differs from pasted output)
    private var wasEnhanced: Bool {
        originalTranscription != llmOutput
    }

    init(originalTranscription: String, llmOutput: String, onSubmit: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.originalTranscription = originalTranscription
        self.llmOutput = llmOutput
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self._correctedText = State(initialValue: llmOutput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Correction")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Original transcription:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(originalTranscription)
                    .font(.body)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

            if wasEnhanced {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LLM output (pasted):")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(llmOutput)
                        .font(.body)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Corrected:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $correctedText)
                    .font(.body)
                    .frame(minHeight: 60)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .focused($isCorrectionFocused)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Explanation (optional):")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Why was this correction needed?", text: $explanation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save Correction") {
                    let explanationValue = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSubmit(correctedText, explanationValue.isEmpty ? nil : explanationValue)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            isCorrectionFocused = true
        }
    }
}
