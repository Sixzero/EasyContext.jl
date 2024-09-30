
codeblock_runner(extractor::CodeBlockExtractor) = begin
    !extractor.skip_code_execution ? execute_shell_commands(extractor; no_confirm=extractor.no_confirm) : OrderedDict{String, CodeBlock}()
end

function execute_shell_commands(extractor::CodeBlockExtractor; no_confirm=false)
    for (command, task) in extractor.shell_scripts
        cb = fetch(task)
        extractor.shell_results[command] = cb
        output = execute_code_block(cb; no_confirm)
        push!(extractor.shell_results[command].run_results, output)
        println("\n\e[36mCommand:\e[0m $command")
        println("\e[36mOutput:\e[0m $output")
    end
end

reset!(extractor::CodeBlockExtractor) = begin
    extractor.last_processed_index=Ref(0) 
    empty!(extractor.shell_scripts)
    empty!(extractor.shell_results)
    extractor.full_content="" 
end
