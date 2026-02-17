
@kwdef struct VimDiffView <: AbstractDiffView end
keywords(::Type{VimDiffView}) = ["vimdiff", "vim"]

register_diffview_subtype!(VimDiffView)

function execute_with_editor(tool::LocalModifyFileTool, view::VimDiffView; no_confirm=false)
    cd(tool.root_path) do
        content_esced = replace(tool.postcontent, "'" => "\\'")
        shell_cmd = "vimdiff $(tool.path) <(echo -e '$content_esced')"
        print_code(get_shortened_code(shell_cmd, 1, 1))
        execute_with_output(`zsh -c $shell_cmd`)
    end
end