
@kwdef mutable struct CommandExtractor
    last_processed_index::Ref{Int} = Ref(0)
    command_tasks::OrderedDict{String, Task} = OrderedDict{String, Task}()
    command_results::OrderedDict{String, Command} = OrderedDict{String, Command}()
    full_content::String = ""
    skip_execution::Bool = false
    no_confirm::Bool = false
    allowed_commands::Set{String} = Set(["MODIFY", "CREATE", "EXECUTE", "SEARCH", "CLICK", "READFILE", "KEY", "SHELL_RUN"])
end

function extract_and_process_tags(new_content::String, extractor::CommandExtractor; instant_return=true, preprocess=(v)->v)
    extractor.full_content *= new_content
    lines = split(extractor.full_content[nextind(extractor.full_content, extractor.last_processed_index[]):end], '\n')
    processed_idx = extractor.last_processed_index[]
    current_content = String[]
    current_tag = nothing

    for (i, line) in enumerate(lines)
        processed_idx += length(line) + 1  # +1 for the newline
        line = rstrip(line)
        
        if !isnothing(current_tag) && line == "/$(current_tag[1])"  # Closing tag
            content = join(current_content, '\n')
            tag = Tag(current_tag[1], current_tag[2], current_tag[3], content)
            
            extractor.tag_tasks[content] = @async_showerr preprocess(tag)
            current_content = String[]
            current_tag = nothing
            extractor.last_processed_index[] = processed_idx
            instant_return && return tag
            
        elseif !isnothing(current_tag) # Content
            push!(current_content, line)
            
        elseif !startswith(line, '/') && !isempty(line) # Opening tag
            parts = split(line)
            tag_name = parts[1]
            if tag_name ∈ extractor.allowed_tags
                args, kwargs = length(parts) > 1 ? parse_arguments(parts[2:end]) : (String[], Dict{String,String}())
                current_tag = (tag_name, args, kwargs)
            end
        end
    end

    !isnothing(current_tag) && warn("Unclosed tag: $(current_tag[1])")
    return nothing
end

function reset!(extractor::CommandExtractor)
    extractor.last_processed_index[] = 0
    empty!(extractor.command_tasks)
    empty!(extractor.command_results)
    extractor.full_content = ""
    return extractor
end

function to_string(command_run_open::String, command_open::String, command_close::String, extractor::CommandExtractor)
    to_string(command_run_open, command_open, command_close, extractor.command_results)
end

function to_string(command_run_open::String, command_open::String, command_close::String, command_results::AbstractDict{String, Command})
    isempty(command_results) && return ""
    
    output = "Previous command executions and their results:\n"
    for (content, command) in command_results
        if command.name ∈ ["EXECUTE", "SEARCH", "SHELL_RUN"]
            shortened_content = get_shortened_code(command2cmd(command))
            output *= """
            $(command_open)
            $shortened_content
            $(command_close)
            $(command_run_open)
            $(haskey(command.kwargs, "result") ? command.kwargs["result"] : "Missing output.")
            $(command_close)
            """
        end
    end
    return output
end
