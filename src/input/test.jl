include("transcribe.jl");
init_assemblyai();
println("Starting audio stream. Speak into your microphone. Press Ctrl+C to stop.");
stream_audio(text -> println("Transcribed: ", text))
