import assemblyai as aai
import os

# Get API key from environment
api_key = os.getenv('ASSEMBLYAI_API_KEY')
if not api_key:
    raise ValueError("ASSEMBLYAI_API_KEY environment variable is not set")

aai.settings.api_key = api_key

def on_open(session_opened: aai.RealtimeSessionOpened):
    print("\nSession ID:", session_opened.session_id)

def on_data(transcript: aai.RealtimeTranscript):
    if not transcript.text:
        return

    if isinstance(transcript, aai.RealtimeFinalTranscript):
        print(f"\r\033[K\033[92m✓ {transcript.text}\033[0m\n")  # Final in green + newline
    else:
        # Partial in gray, overwriting the line
        print(f"\r\033[K\033[90m⋯ {transcript.text}...\033[0m", end="", flush=True)

def on_error(error: aai.RealtimeError):
    print("\033[91mError:", error, "\033[0m")

def on_close():
    print("Closing Session")

def stream_mic():
    transcriber = aai.RealtimeTranscriber(
        sample_rate=16000,
        on_data=on_data,
        on_error=on_error,
        on_open=on_open,
        on_close=on_close,
        # Important: We want both partial and final transcripts
        enable_partials=True
    )

    print("Starting audio stream. Speak into your microphone. Press Ctrl+C to stop.")
    print("Gray text: partial transcripts (drafts)")
    print("Green text: final transcripts\n")
    
    try:
        transcriber.connect()
        microphone_stream = aai.extras.MicrophoneStream(sample_rate=16000)
        transcriber.stream(microphone_stream)
    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        transcriber.close()

if __name__ == "__main__":
    stream_mic()
