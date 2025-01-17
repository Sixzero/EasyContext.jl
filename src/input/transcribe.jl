using PyCall

function init_assemblyai()
    api_key = get(ENV, "ASSEMBLYAI_API_KEY", "")
    isempty(api_key) && error("ASSEMBLYAI_API_KEY environment variable is not set")
    py"""
    import assemblyai as aai
    aai.settings.api_key = $api_key
    """
end

function transcribe_audio(file_url::String)
    py"""
    transcriber = aai.Transcriber()
    transcript = transcriber.transcribe($file_url)
    
    if transcript.status == aai.TranscriptStatus.error:
        raise Exception(transcript.error)
        
    return transcript.text
    """
    return py"transcript.text"
end

function stream_audio(callback)
    py"""
    import assemblyai as aai
    import pyaudio
    
    def stream_mic():
        # Initialize PyAudio and set up microphone stream
        audio = pyaudio.PyAudio()
        stream = audio.open(
            format=pyaudio.paFloat32,
            channels=1,
            rate=16000,
            input=True,
            frames_per_buffer=1024
        )
        
        # Initialize real-time transcriber
        transcriber = aai.RealtimeTranscriber(
            sample_rate=16000,
            on_data=lambda transcript: $callback(transcript.text)
        )
        
        with transcriber.connect() as socket:
            while True:
                try:
                    data = stream.read(1024)
                    socket.send_audio(data)
                except KeyboardInterrupt:
                    break
                
        stream.stop_stream()
        stream.close()
        audio.terminate()
    """
    py"stream_mic"()
end