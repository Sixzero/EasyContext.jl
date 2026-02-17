
@kwdef struct MeldDiffView <: AbstractDiffView end
keywords(::Type{MeldDiffView}) = ["meld"]

register_diffview_subtype!(MeldDiffView)

function execute_with_editor(tool::LocalModifyFileTool, view::MeldDiffView; no_confirm=false)
    cd(tool.root_path) do
        delimiter = get_unique_eof(tool.postcontent)
        shell_cmd = "meld $(tool.path) <(cat <<'$delimiter'\n$(tool.postcontent)\n$delimiter\n)"
        print_code(get_shortened_code(shell_cmd, 1, 1))
        execute_with_output(`zsh -c $shell_cmd`)
    end
end