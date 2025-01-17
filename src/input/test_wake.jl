include("wake_word.jl")

# Get access key from environment
access_key = get(ENV, "PICOVOICE_ACCESS_KEY", "")
isempty(access_key) && error("PICOVOICE_ACCESS_KEY environment variable is not set")

println("Starting wake word detection system...")
println("Press Ctrl+C to exit")

# Create callback function
function wake_word_callback(keyword_index, keyword)
    println("Wake word detected: '$(keyword)' (index: $(keyword_index))")
end

# Initialize with default wake words
init_wake_word_system(
    access_key,
    keywords=["picovoice", "bumblebee"],
    callback=wake_word_callback
)

# Example with custom wake word (commented out)
# init_wake_word_system(
#     access_key,
#     keyword_paths=["path/to/custom/wake_word.ppn"],
#     model_path="path/to/language_model.pv",  # Optional for non-English
#     callback=wake_word_callback
# )
