# using AISH: AIState, streaming_process_question
using REPL
using ReplMaker
using REPL.LineEdit

function create_ai_repl(state::AIState)
    shell_results = Dict{String, String}()
    function ai_parser(input::String)
        if !isempty(strip(input))
            println("\nProcessing your request...")
            _, shell_results = streaming_process_question(state, input, shell_results)
        end
        return
    end

    prompt = () -> "AISH> "

    ai_mode = initrepl(
        ai_parser;
        prompt_text=prompt,
        prompt_color=:cyan,
        start_key=')',
        mode_name=:ai,
        # valid_input_checker=REPL.complete_julia
    )


    return ai_mode
end

function start_ai_repl(state::AIState)
    ai_mode = create_ai_repl(state)
    println("AI REPL mode initialized. Press ')' to enter and backspace to exit.")
end

