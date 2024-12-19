
@kwdef mutable struct ModifyFileCommand <: AbstractCommand
    id::UUID = uuid4()
    language::String = "sh"
    file_path::String
    root_path::String
    content::String
    postcontent::String
end
function ModifyFileCommand(cmd::CommandTag)
    # Clean up file path by removing trailing '>'
    file_path = endswith(cmd.args, ">") ? chop(cmd.args) : cmd.args

    language, content = parse_code_block(cmd.content)
    ModifyFileCommand(
        language=language,
        file_path=file_path,
        root_path=get(cmd.kwargs, "root_path", ""),
        content=content,
        postcontent=""
    )
end
instantiate(::Val{Symbol(MODIFY_FILE_TAG)}, cmd::CommandTag) = ModifyFileCommand(cmd)

commandname(cmd::Type{ModifyFileCommand}) = MODIFY_FILE_TAG
get_description(cmd::Type{ModifyFileCommand}) = """
To modify the file, always try to highlight the changes and relevant cmd_code and use comment like: 
// ... existing cmd_code ... 
comments indicate where unchanged cmd_code has been skipped and spare rewriting the whole cmd_code base again. 
To modify or update an existing file "$(MODIFY_FILE_TAG)" tags followed by the filepath and the codeblock like this and closed with an "$(END_OF_BLOCK_TAG)":
$(MODIFY_FILE_TAG) path/to/file1
$(code_format("code_changes", "language"))
$(END_OF_BLOCK_TAG)

So to update and modify existing files use this pattern to virtually create a file changes that is then applied by an external tool comments like:
// ... existing cmd_code ... 

$(MODIFY_FILE_TAG) path/to/file2
$(code_format("code_changes_with_existing_code_comments", "language"))
$(END_OF_BLOCK_TAG)

To modify the codebase with changes try to focus on changes and indicate if codes are unchanged and skipped:
$(MODIFY_FILE_TAG) filepath
$(code_format("code_changes_without_unchanged_code", "language"))
$(END_OF_BLOCK_TAG)
It is important you ALWAYS close the tag with "$(END_OF_BLOCK_TAG)".
"""
stop_sequence(cmd::Type{ModifyFileCommand}) = ""






execute(cmd::ModifyFileCommand; no_confirm=false) = execute(cmd, CURRENT_EDITOR; no_confirm)
preprocess(cmd::ModifyFileCommand) = LLM_conditional_apply_changes(cmd)



abstract type AbstractDiffView end
keywords(::Type{<:AbstractDiffView}) = String[]
keywords(view::AbstractDiffView) = keywords(typeof(view))

const DIFFVIEW_SUBTYPES = Vector{Type{<:AbstractDiffView}}()
function register_diffview_subtype!(T::Type{<:AbstractDiffView})
    push!(DIFFVIEW_SUBTYPES, T)
end

include("../../building_block/DiffViews.jl")

# Interface for AbstractDiffView
execute(cmd::ModifyFileCommand, editor::AbstractDiffView; no_confirm=false) =
    @warn "Unimplemented execute(::ModifyFileCommand, ::$(typeof(editor)))!"


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
    @show editor_name
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
    @show typeof(editor)
    CURRENT_EDITOR = editor
    !isnothing(port) && (ENV["MELD_PORT"] = port)

    return true
end
    
CURRENT_EDITOR = MonacoMeldDiffView()  # Default editor