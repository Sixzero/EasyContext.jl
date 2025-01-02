
@kwdef struct VimDiffView <: AbstractDiffView end
keywords(::Type{VimDiffView}) = ["vimdiff", "vim"]

register_diffview_subtype!(VimDiffView)

function execute(cmd::ModifyFileTool, view::VimDiffView; no_confirm=false)
    content_esced = replace(cmd.postcontent, "'" => "\\'")
    cmd_code = "vimdiff $(cmd.file_path) <(echo -e '$content_esced')"
    print_code(get_shortened_code(cmd_code, 1, 1))
    cmd_all_info_modify(`zsh -c $cmd_code`)
end