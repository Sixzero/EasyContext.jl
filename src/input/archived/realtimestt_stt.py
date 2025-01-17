import os
import sys
from RealtimeSTT import AudioToTextRecorder
import time

def process_stabilized(text):
    if text and text.strip():
        text = text.strip()
        print(f"{text}")

def on_wakeword():
    print("✨ Wake word detected!")

def stream_mic(
    model="tiny.en",
    device="cpu",
    language="en",
):
    print("Starting audio stream. Say 'hey computer' to activate. Press Ctrl+C to stop.\n")
    
    recorder = AudioToTextRecorder(
        model=model,
        device=device,
        language=language,
        enable_realtime_transcription=False,
        on_realtime_transcription_stabilized=process_stabilized,
        
        # Wake word settings
        wakeword_backend="oww",
        openwakeword_inference_framework="onnx",
        wake_words_sensitivity=0.5,
        on_wakeword_detected=on_wakeword,
        
        # Voice activity settings
        silero_sensitivity=0.7,
        post_speech_silence_duration=0.5,
        min_length_of_recording=0.5,
        
        ensure_sentence_starting_uppercase=True,
        ensure_sentence_ends_with_period=True,
        beam_size=5,
        
        debug_mode=True,
        spinner=False
    )
    
    def audio_callback(indata, frames, time, status):
        if status:
            print('Error:', status)
        # Process audio with wake word detector
        audio_data = indata[:, 0]
        prediction = detector.predict(audio_data)
        
        # Check if wake word detected
        for model_name in prediction.keys():
            if prediction[model_name] > 0.5:
                on_wakeword()
    
    try:
        with sd.InputStream(channels=1, callback=audio_callback,
                          samplerate=16000, blocksize=1024):
            recorder.start()
            while True:
                time.sleep(0.1)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        recorder.stop()
        recorder.shutdown()

if __name__ == "__main__":
    stream_mic()
