include("diffviews/DiffViews.jl")

@kwdef mutable struct ModifyFileTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "sh"
    file_path::String
    root_path::String
    content::String
    postcontent::String
    model=["gem20f", "orqwenplus", "gpt4o"] # the model handling the LLM apply
end
function create_tool(::Type{ModifyFileTool}, cmd::ToolTag)
    # Clean up file path by removing trailing '>'
    file_path = endswith(cmd.args, ">") ? chop(cmd.args) : cmd.args

    language, content = parse_code_block(cmd.content)
    ModifyFileTool(
        language=language,
        file_path=file_path,
        root_path=get(cmd.kwargs, "root_path", "."),
        content=content,
        postcontent=""
    )
end

toolname(cmd::Type{ModifyFileTool}) = MODIFY_FILE_TAG
get_description(cmd::Type{ModifyFileTool}) = MODIFY_FILE_DESCRIPTION(cmd)
MODIFY_FILE_DESCRIPTION(cmd) = """
To modify or update an existing file "$(MODIFY_FILE_TAG)" tags followed by the filepath and the codeblock like this and finished with an "```$(END_OF_CODE_BLOCK)":

$(MODIFY_FILE_TAG) path/to/file1
$(code_format("code_changes", "language"))

So to update and modify existing files use this pattern to virtually create a file changes that is then applied by an external tool comments like:
// ... existing code ...

$(MODIFY_FILE_TAG) path/to/file2
$(code_format("code_changes_with_existing_code_comments", "language"))

To modify the codebase with changes try to focus on changes and indicate if codes are unchanged and skipped:
$(MODIFY_FILE_TAG) filepath
$(code_format("code_changes_without_unchanged_code", "language"))

To modify the file, always try to highlight the changes and relevant code and use comment like:
// ... existing code ...
comments indicate where unchanged code has been skipped and spare rewriting the whole codebase again.

It is important you ALWAYS close the code block with "```$(END_OF_CODE_BLOCK)" in the next line.
"""
MODIFY_FILE_DESCRIPTION_V2(cmd::Type{ModifyFileTool}) = """
To modify or update an existing file "$(MODIFY_FILE_TAG)" tags followed by the filepath and the codeblock like this and finished with an "```$(END_OF_CODE_BLOCK)".

Examples:
$(MODIFY_FILE_TAG) path/to/file1
$(code_format("multiline_code_changes", "language"))

$(MODIFY_FILE_TAG) path/to/file2
$(code_format(""" # ... existing code ...
some same lines
new line with code changes
some same lines
 # ... existing code ...""", "language"))

$(MODIFY_FILE_TAG) filepath
$(code_format("code_changes_without_unchanged_code", "language"))

To modify the file, always try to highlight the changes and relevant code and try to skip the unchanged code parts. Use comments like:
"... existing code ..."
comments indicate where unchanged code has been skipped to spare rewriting the whole codebase again.

To make multiple changes to the same file, list ALL changes in a single MODIFY block for that file and if necessary use "...existing code..." block to separate the changes.

Always close the code block with "```$(END_OF_CODE_BLOCK)".
"""
stop_sequence(cmd::Type{ModifyFileTool}) = ""
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