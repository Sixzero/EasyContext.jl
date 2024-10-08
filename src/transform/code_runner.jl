
codeblock_runner(extractor::CodeBlockExtractor; no_confirm=false) = begin
    return !extractor.skip_code_execution ? execute_shell_commands(extractor; no_confirm) : OrderedDict{String, CodeBlock}()
end

function execute_shell_commands(extractor::CodeBlockExtractor; no_confirm=false)
    for (command, task) in extractor.shell_scripts
        cb = fetch(task)
        if cb !== nothing
            extractor.shell_results[command] = cb
            output = execute_code_block(cb; no_confirm)
            push!(extractor.shell_results[command].run_results, output)
            # println("\n\e[36mCommand:\e[0m $command")
            !isempty(strip(output)) && println("\e[36mOutput:\e[0m $output")
        else
            @warn "TODO We couldn't run the block, there might have been an error." # we think the error is because @async_showerr crashed and returned nothing.
            println("\e[31mWarning:\e[0m Task for command '$command' returned nothing")
        end
    end
    return extractor.shell_results
end

reset!(extractor::CodeBlockExtractor) = begin
    extractor.last_processed_index=Ref(0) 
    empty!(extractor.shell_scripts)
    empty!(extractor.shell_results)
    extractor.full_content="" 
end
