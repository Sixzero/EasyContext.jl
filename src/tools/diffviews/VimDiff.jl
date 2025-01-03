
@kwdef struct VimDiffView <: AbstractDiffView end
keywords(::Type{VimDiffView}) = ["vimdiff", "vim"]

register_diffview_subtype!(VimDiffView)

function execute(tool::ModifyFileTool, view::VimDiffView; no_confirm=false)
    content_esced = replace(tool.postcontent, "'" => "\\'")
    shell_cmd = "vimdiff $(tool.file_path) <(echo -e '$content_esced')"
    print_code(get_shortened_code(shell_cmd, 1, 1))
    cmd_all_info_modify(`zsh -c $shell_cmd`)
end