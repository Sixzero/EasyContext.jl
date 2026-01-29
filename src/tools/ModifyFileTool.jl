include("diffviews/DiffViews.jl")

using ToolCallFormat: ParsedCall

@kwdef mutable struct ModifyFileTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "sh"
    file_path::String
    root_path::String
    content::String
    postcontent::String
    model=["gem20f", "orqwenplus", "gpt4o"] # the model handling the LLM apply
end
function create_tool(::Type{ModifyFileTool}, call::ParsedCall)
    file_path_pv = get(call.kwargs, "file_path", nothing)
    file_path = file_path_pv !== nothing ? file_path_pv.value : ""
    # Clean up file path by removing trailing '>'
    file_path = endswith(file_path, ">") ? chop(file_path) : file_path

    # Content comes from call.content or kwargs
    content_pv = get(call.kwargs, "content", nothing)
    raw_content = content_pv !== nothing ? content_pv.value : call.content
    language, content = parse_code_block(raw_content)

    root_path_pv = get(call.kwargs, "root_path", nothing)
    ModifyFileTool(
        language=language,
        file_path=file_path,
        root_path=root_path_pv !== nothing ? root_path_pv.value : ".",
        content=content,
        postcontent=""
    )
end

toolname(cmd::Type{ModifyFileTool}) = "modify_file"
const MODIFYFILE_SCHEMA = (
    name = "modify_file",
    description = "Modify an existing file with code changes. Use '... existing code ...' comments to skip unchanged parts",
    params = [
        (name = "file_path", type = "string", description = "Path to file to modify", required = true),
        (name = "content", type = "codeblock", description = "Code changes", required = true),
    ]
)
get_tool_schema(::Type{ModifyFileTool}) = MODIFYFILE_SCHEMA
get_description(cmd::Type{ModifyFileTool}) = description_from_schema(MODIFYFILE_SCHEMA)
tool_format(::Type{ModifyFileTool}) = :multi_line

execute_required_tools(::ModifyFileTool) = false
execute(cmd::ModifyFileTool; no_confirm=false) = execute(cmd, CURRENT_EDITOR; no_confirm)
preprocess(cmd::ModifyFileTool) = LLM_conditional_apply_changes(cmd)

function get_shortened_code(code::String, head_lines::Int=4, tail_lines::Int=3)
    lines = split(code, '\n')
    total_lines = length(lines)

    if total_lines <= head_lines + tail_lines
        return code
    else
        head = join(lines[1:head_lines], '\n')
        tail = join(lines[end-tail_lines+1:end], '\n')
        return "$head\n...\n$tail"
    end
end

# Interface for AbstractDiffView
execute(cmd::ModifyFileTool, editor::AbstractDiffView; no_confirm=false) =
    @warn "Unimplemented execute(::ModifyFileTool, ::$(typeof(editor)))!"

include("diffviews/MeldDiff.jl")
include("diffviews/VimDiff.jl")
include("diffviews/MonacoMeldDiff.jl")

function get_available_editors()
    return sort(unique(vcat([keywords(T) for T in DIFFVIEW_SUBTYPES]...)))
end
# Dynamically get available editors
function get_editor(editor_name::AbstractString)
    editor_base = lowercase(editor_name)
    for T in DIFFVIEW_SUBTYPES
        editor_base in keywords(T) && return T()
    end
    return nothing
end

function set_editor(editor_name::AbstractString)
    global CURRENT_EDITOR
    # Handle editor:port format
    editor_base, port = if occursin(':', editor_name)
        parts = split(editor_name, ':')
        if length(parts) != 2 || isnothing(tryparse(Int, parts[2]))
            @warn "Invalid port number"
            return false
        end
        parts[1], parts[2]
    else
        editor_name, nothing
    end

    # Validate and set editor
    editor = get_editor(editor_base)
    if isnothing(editor)
        available = join(get_available_editors(), ", ")
        @warn "Unknown editor. Available editors: $available"
        return false
    end

    # Set the editor and port
    CURRENT_EDITOR = editor
    !isnothing(port) && (ENV["MELD_PORT"] = port)

    return true
end


function LLM_conditional_apply_changes(tool::ModifyFileTool)
    original_content, ai_generated_content = LLM_apply_changes_to_file(tool)
    tool.postcontent = ai_generated_content
    tool
end

LLM_apply_changes_to_file(tool::ModifyFileTool) = LLM_apply_changes_to_file(tool.root_path, tool.file_path, tool.content, tool.language, tool.model)
function LLM_apply_changes_to_file(root_path::String, file_path::String, content::String, language::String, models::Vector{String})
    original_content = ""
    cd(root_path) do
        file_path, line_range = parse_source(file_path)
        
        # Use the utility function to handle path expansion
        path = expand_path(file_path)
        
        if isfile(path)
            original_content = read(path, String)
        else
            @warn "WARNING! Unexisting file! $(file_path) (expanded: $(path)) pwd: $(pwd()) root_path: $(root_path)"
            content
        end
    end
    isempty(original_content) && return content, content

    ai_generated_content = apply_modify_auto(original_content, content; language, model=models)

    original_content, String(ai_generated_content)
end
# TODO maybe chunks should have this? but just wut a full_parse on the location it is used which returns full content without line cuts? instead of reparse?
function parse_source(source::String)
    source_nospace = split(source, ' ')[1]
    parts = split(source_nospace, ':')
    length(parts) == 1 && return parts[1], nothing
    start_line, end_line = parse.(Int, split(parts[2], '-'))
    return parts[1], (start_line, end_line)
end


CURRENT_EDITOR = MonacoMeldDiffView()  # Default editor