
codeblock_runner(extractor::CodeBlockExtractor) = !extractor.skip_code_execution ? execute_shell_commands(extractor; no_confirm=extractor.no_confirm) : OrderedDict{String, CodeBlock}()

function execute_shell_commands(extractor::CodeBlockExtractor; no_confirm=false)
    for (command, task) in extractor.shell_scripts
        extractor.shell_results[command] = fetch(task)
        # @show processed_command
        output = execute_code_block(processed_command; no_confirm)
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
