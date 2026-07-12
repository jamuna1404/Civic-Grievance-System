import os
import wave
import struct
import math
from app.ml.asr import transcribe

def generate_test_wav(filepath, duration_sec=1.5, sample_rate=16000):
    """
    Programmatically generate a standard 16kHz 16-bit mono WAV file containing a sine tone.
    This creates a reliable, self-contained test fixture without needing external downloads.
    """
    print(f"Generating temporary audio fixture: {filepath} ({duration_sec}s at {sample_rate}Hz)...")
    with wave.open(filepath, 'wb') as wav_file:
        n_channels = 1
        sampwidth = 2  # 16-bit
        n_frames = int(sample_rate * duration_sec)
        wav_file.setparams((n_channels, sampwidth, sample_rate, n_frames, 'NONE', 'not compressed'))
        
        # 440Hz sine wave (A4 note)
        frequency = 440.0
        for i in range(n_frames):
            value = int(16384.0 * math.sin(2.0 * math.pi * frequency * i / sample_rate))
            data = struct.pack('<h', value)
            wav_file.writeframesraw(data)

def main():
    fixture_path = "test_fixture.wav"
    try:
        # Generate the test fixture
        generate_test_wav(fixture_path)
        
        print("\n--- Running Speech-to-Text Module ---")
        # Run transcription
        result = transcribe(fixture_path)
        
        print("\nSUCCESS! Transcription results:")
        print(f"Detected Language : {result['detected_language']} (Confidence: {result['confidence']:.2f})")
        print(f"Audio Duration    : {result['duration']:.2f} seconds")
        print(f"Transcribed Text  : '{result['text']}'")
        
    except Exception as e:
        print(f"\nASR Test Failed with Error: {str(e)}")
        import traceback
        traceback.print_exc()
    finally:
        # Cleanup
        if os.path.exists(fixture_path):
            os.remove(fixture_path)
            print(f"Removed temporary fixture: {fixture_path}")

if __name__ == "__main__":
    main()
