# Transcribe test - requires PythonCall to be loaded
# using PythonCall  # uncomment to enable transcription
using EasyContext: init_assemblyai, stream_audio
init_assemblyai();
println("Starting audio stream. Speak into your microphone. Press Ctrl+C to stop.");
stream_audio(text -> println("Transcribed: ", text))
#%%
import PromptingTools: CerebrasOpenAISchema, aigenerate
aigenerate(CerebrasOpenAISchema(), "Tell me a joke."; model="gpt-oss-120b") # works

using StreamCallbacks
cb = StreamCallback()
aigenerate(CerebrasOpenAISchema(), "Tell me a joke."; model="gpt-oss-120b", streamcallback=cb) # gets stuck
