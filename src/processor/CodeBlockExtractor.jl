
@kwdef mutable struct CodeBlockExtractor
    last_processed_index::Ref{Int} = Ref(0)
    shell_scripts::OrderedDict{String, Task} = OrderedDict{String, Task}()
    shell_results::OrderedDict{String, CodeBlock} = OrderedDict{String, CodeBlock}()
    full_content::String = ""
    skip_code_execution::Bool = false
    no_confirm::Bool = false
end

function is_opener_ticks(line::AbstractString, nesting_level::Int)
    if nesting_level == 0
        return startswith(line, "```")
    else
        return startswith(line, "```") && length(strip(line)) > 3
    end
end

function is_closer_ticks(line::AbstractString)
    return startswith(line, "```") && (length(line) == 3 || all(isspace, line[4:end]))
end

function extract_and_preprocess_codeblocks(new_content::String, extractor::CodeBlockExtractor; instant_return=true, preprocess=(v)-> v)
    extractor.full_content *= new_content
    lines = split(extractor.full_content[nextind(extractor.full_content, extractor.last_processed_index[]):end], '\n')
    current_command = String[]
    nesting_level = 0
    cmd_type = :DEFAULT
    block_type = ""
    file_path = ""

    for (i, line) in enumerate(lines)
        if startswith(line, "MODIFY ")        
            file_path = expanduser(String(strip(line[8:end])))
            cmd_type = :MODIFY
        elseif startswith(line, "CREATE ")
            file_path = expanduser(String(strip(line[8:end])))
            cmd_type = :CREATE
        elseif is_opener_ticks(line, nesting_level)
            nesting_level += 1
            if nesting_level == 1
                block_type = length(line) > 3 ? String(strip(line[4:end])) : ""
            end
        elseif is_closer_ticks(line)
            nesting_level -= 1
            
            if nesting_level == 0
                command = join(current_command, '\n')
                cb = CodeBlock(;file_path, type=cmd_type, language=block_type, pre_content=command)
                extractor.shell_scripts[command] = @async_showerr preprocess(cb)
                current_command = String[]
                cmd_type = :DEFAULT
                block_type = ""
                file_path = ""
                extractor.last_processed_index[] = length(extractor.full_content)
                
                instant_return && return cb
            end
        elseif nesting_level > 0
            push!(current_command, line)
        end
        
        # if !in_block
        #     last_processed_char += length(line) + 1  # +1 for the newline
        # end
    end

    return nothing
end

to_string(tag::String, element::String, cb_ext::CodeBlockExtractor) = to_string(tag::String, element::String, cb_ext.shell_results)
to_string(tag::String, element::String, shell_results::AbstractDict{String, CodeBlock}) = begin
    return isempty(shell_results) ? "" : """
    <$tag>
    $(join(["""<$element shortened>
    $(get_shortened_code(codestr(codeblock)))
    </$element>
    <$(SHELL_RUN_RESULT)>
    $(codeblock.run_results[end])
    </$(SHELL_RUN_RESULT)>
    """ for (code, codeblock) in shell_results], "\n"))
    </$tag>
    """
end
