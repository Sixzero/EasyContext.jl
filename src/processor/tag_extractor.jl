
@kwdef mutable struct TagExtractor
    last_processed_index::Ref{Int} = Ref(0)
    tag_tasks::OrderedDict{String, Task} = OrderedDict{String, Task}()
    tag_results::OrderedDict{String, Tag} = OrderedDict{String, Tag}()
    full_content::String = ""
    skip_execution::Bool = false
    no_confirm::Bool = false
    allowed_tags::Set{String} = Set(["MODIFY", "CREATE", "EXECUTE", "SEARCH"])
end

function extract_and_process_tags(new_content::String, extractor::TagExtractor; instant_return=true, preprocess=(v)->v)
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

function reset!(extractor::TagExtractor)
    extractor.last_processed_index[] = 0
    empty!(extractor.tag_tasks)
    empty!(extractor.tag_results)
    extractor.full_content = ""
    return extractor
end

function to_string(tag_run_open::String, tag_open::String, tag_close::String, extractor::TagExtractor)
    to_string(tag_run_open, tag_open, tag_close, extractor.tag_results)
end

function to_string(tag_run_open::String, tag_open::String, tag_close::String, tag_results::AbstractDict{String, Tag})
    isempty(tag_results) && return ""
    
    output = "Previous tag executions and their results:\n"
    for (content, tag) in tag_results
        if tag.name ∈ ["EXECUTE", "SEARCH"]  # Only show results for non-file-modifying tags
            shortened_content = get_shortened_code(tag2cmd(tag))
            output *= """
            $(tag_open)
            $shortened_content
            $(tag_close)
            $(tag_run_open)
            $(haskey(tag.kwargs, "result") ? tag.kwargs["result"] : "Missing output.")
            $(tag_close)
            """
        end
    end
    return output
end
