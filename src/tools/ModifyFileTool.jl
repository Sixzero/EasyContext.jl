include("diffviews/DiffViews.jl")

@kwdef mutable struct ModifyFileTool <: AbstractTool
    id::UUID = uuid4()
    language::String = "sh"
    file_path::String
    root_path::String
    content::String
    postcontent::String
    model="gem20f" # the model handling the LLM apply
end
function ModifyFileTool(cmd::ToolTag)
    # Clean up file path by removing trailing '>'
    file_path = endswith(cmd.args, ">") ? chop(cmd.args) : cmd.args

    language, content = parse_code_block(cmd.content)
    ModifyFileTool(
        language=language,
        file_path=file_path,
        root_path=get(cmd.kwargs, "root_path", ""),
        content=content,
        postcontent=""
    )
end
instantiate(::Val{Symbol(MODIFY_FILE_TAG)}, cmd::ToolTag) = ModifyFileTool(cmd)

toolname(cmd::Type{ModifyFileTool}) = MODIFY_FILE_TAG
get_description(cmd::Type{ModifyFileTool}) = """
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
stop_sequence(cmd::Type{ModifyFileTool}) = ""

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

function LLM_apply_changes_to_file(tool::ModifyFileTool)
    original_content = ""
    cd(tool.root_path) do
        file_path, line_range = parse_source(tool.file_path)
        if isfile(file_path)
            original_content = read(file_path, String)
        else
            @warn "WARNING! Unexisting file! $(file_path) pwd: $(pwd())"
            tool.content
        end
    end
    isempty(original_content) && return tool.content, tool.content

    is_patch_file = tool.language=="patch"
    merge_prompt = is_patch_file ? get_patch_merge_prompt : get_merge_prompt_v1
    # Check file size and choose appropriate method
    if length(original_content) > 10_000
        ai_generated_content = apply_modify_by_replace(original_content, tool.content)
    else

        ai_generated_content = apply_modify_by_llm(original_content, tool.content; merge_prompt, model=tool.model)
    end

    original_content, ai_generated_content
end

CURRENT_EDITOR = MonacoMeldDiffView()  # Default editor