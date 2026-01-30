using PythonCall

# Lazy load Python modules
const _aai = Ref{Py}()
const _pyaudio = Ref{Py}()

function ensure_assemblyai()
    if !isassigned(_aai)
        _aai[] = pyimport("assemblyai")
    end
    _aai[]
end

function ensure_pyaudio()
    if !isassigned(_pyaudio)
        _pyaudio[] = pyimport("pyaudio")
    end
    _pyaudio[]
end

function init_assemblyai()
    api_key = get(ENV, "ASSEMBLYAI_API_KEY", "")
    isempty(api_key) && error("ASSEMBLYAI_API_KEY environment variable is not set")
    aai = ensure_assemblyai()
    aai.settings.api_key = api_key
end

function transcribe_audio(file_url::String)
    aai = ensure_assemblyai()
    transcriber = aai.Transcriber()
    transcript = transcriber.transcribe(file_url)

    if pyconvert(Bool, transcript.status == aai.TranscriptStatus.error)
        error(pyconvert(String, transcript.error))
    end

    return pyconvert(String, transcript.text)
end

function stream_audio(callback)
    aai = ensure_assemblyai()
    pyaudio = ensure_pyaudio()

    # Initialize PyAudio and set up microphone stream
    audio = pyaudio.PyAudio()
    stream = audio.open(;
        format=pyaudio.paFloat32,
        channels=1,
        rate=16000,
        input=true,
        frames_per_buffer=1024
    )

    # Create a Python callback wrapper
    py_callback = pyfunction(text -> callback(pyconvert(String, text)))

    # Initialize real-time transcriber
    transcriber = aai.RealtimeTranscriber(;
        sample_rate=16000,
        on_data=pyfunction(transcript -> py_callback(transcript.text))
    )

    # Connect and stream
    socket = transcriber.connect().__enter__()
    try
        while true
            try
                data = stream.read(1024)
                socket.send_audio(data)
            catch e
                if e isa InterruptException
                    break
                end
                rethrow(e)
            end
        end
    finally
        socket.__exit__(nothing, nothing, nothing)
        stream.stop_stream()
        stream.close()
        audio.terminate()
    end
end
