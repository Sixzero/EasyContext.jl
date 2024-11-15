
using Base.Threads

codeblock_runner(extractor::CodeBlockExtractor; no_confirm=false, async=false) = !extractor.skip_code_execution ? execute_shell_commands(extractor; no_confirm, async) : OrderedDict{String, CodeBlock}()

function execute_shell_commands(extractor::CodeBlockExtractor; no_confirm=false, async=false)
    for (command, task) in extractor.shell_scripts
        cb = fetch(task)
        if cb !== nothing
            extractor.shell_results[command] = cb
            push!(extractor.shell_results[command].run_results, execute_code_block(cb; no_confirm))
        else
            @warn "TODO We couldn't run the block, there might have been an error."
            println("\e[31mWarning:\e[0m Task for command '$command' returned nothing")
        end
    end
    (async) && (println(); dialog())  # Show dialog arrow in async context or when explicitly set
    return extractor.shell_results
end

reset!(extractor::CodeBlockExtractor) = begin
    extractor.last_processed_index=Ref(0) 
    empty!(extractor.shell_scripts)
    empty!(extractor.shell_results)
    extractor.full_content="" 
end
