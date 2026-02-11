"""Real-time streaming microphone transcription with Parakeet v3.

Shows live partial transcriptions that update as you speak (like DeepGram),
then finalises the result when silence is detected.

Usage:
    python examples/mic_parakeet_streaming.py
    python examples/mic_parakeet_streaming.py --interval 0.8
    python examples/mic_parakeet_streaming.py --silence-duration 1.0
"""

import argparse
import sys
import time
import queue

import numpy as np
import sounddevice as sd
import mlx.core as mx

from mlx_audio.stt.utils import load_model


def transcribe(model, audio_np):
    """Run a single non-streaming transcription on an audio buffer."""
    audio_mx = mx.array(audio_np, dtype=mx.bfloat16)
    result = model.generate(audio_mx)
    mx.clear_cache()
    return result.text.strip() if hasattr(result, "text") else ""


def main():
    parser = argparse.ArgumentParser(
        description="Real-time streaming microphone transcription with Parakeet v3"
    )
    parser.add_argument(
        "--model",
        default="mlx-community/parakeet-tdt-0.6b-v3",
        help="Model to use (default: mlx-community/parakeet-tdt-0.6b-v3)",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="How often to re-transcribe the buffer in seconds (default: 1.0)",
    )
    parser.add_argument(
        "--silence-duration",
        type=float,
        default=0.7,
        help="Seconds of silence to finalise an utterance (default: 0.7)",
    )
    parser.add_argument(
        "--energy-threshold",
        type=float,
        default=0.005,
        help="RMS energy threshold for speech detection (default: 0.005)",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=16000,
        help="Microphone sample rate (default: 16000)",
    )
    args = parser.parse_args()

    print(f"Loading model: {args.model}")
    model = load_model(args.model)
    print("Model loaded.\n")

    sample_rate = args.sample_rate
    block_duration = 0.03  # 30ms frames
    block_size = int(sample_rate * block_duration)
    silence_blocks = int(args.silence_duration / block_duration)
    interval_blocks = int(args.interval / block_duration)

    audio_queue = queue.Queue()

    def audio_callback(indata, frames, time_info, status):
        if status:
            print(f"  [audio: {status}]", file=sys.stderr)
        audio_queue.put(indata[:, 0].copy())

    print(f"  interval={args.interval}s  silence={args.silence_duration}s  threshold={args.energy_threshold}")
    print("  Speak into your microphone. Ctrl+C to stop.\n")
    print("-" * 60)

    stream = sd.InputStream(
        samplerate=sample_rate,
        blocksize=block_size,
        channels=1,
        dtype="float32",
        callback=audio_callback,
    )

    try:
        with stream:
            frames = []
            silent_count = 0
            blocks_since_transcription = 0
            speaking = False
            last_partial = ""

            while True:
                block = audio_queue.get()
                rms = np.sqrt(np.mean(block**2))
                is_speech = rms > args.energy_threshold

                if is_speech:
                    silent_count = 0
                    if not speaking:
                        speaking = True
                    frames.append(block)
                    blocks_since_transcription += 1
                elif speaking:
                    silent_count += 1
                    frames.append(block)
                    blocks_since_transcription += 1
                else:
                    continue

                # --- Periodic partial transcription while speaking ---
                if speaking and silent_count < silence_blocks and blocks_since_transcription >= interval_blocks:
                    blocks_since_transcription = 0
                    audio_data = np.concatenate(frames)
                    text = transcribe(model, audio_data)
                    if text and text != last_partial:
                        last_partial = text
                        # Overwrite line in-place
                        sys.stdout.write(f"\r\033[K  \033[90m▸ {text}\033[0m")
                        sys.stdout.flush()

                # --- Silence detected → finalise ---
                if speaking and silent_count >= silence_blocks:
                    audio_data = np.concatenate(frames)
                    duration = len(audio_data) / sample_rate
                    t0 = time.time()
                    text = transcribe(model, audio_data)
                    elapsed = time.time() - t0

                    # Clear the partial line and print the final result
                    sys.stdout.write("\r\033[K")
                    if text:
                        print(f"  \033[1m{text}\033[0m  \033[90m({duration:.1f}s audio, {elapsed:.2f}s)\033[0m")
                    sys.stdout.flush()

                    # Reset state
                    frames = []
                    silent_count = 0
                    blocks_since_transcription = 0
                    speaking = False
                    last_partial = ""

    except KeyboardInterrupt:
        print("\n" + "-" * 60)
        print("Stopped.")


if __name__ == "__main__":
    main()
