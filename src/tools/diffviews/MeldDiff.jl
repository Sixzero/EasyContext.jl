
@kwdef struct MeldDiffView <: AbstractDiffView end
keywords(::Type{MeldDiffView}) = ["meld"]

register_diffview_subtype!(MeldDiffView)

function execute(tool::ModifyFileTool, view::MeldDiffView; no_confirm=false)
    delimiter = get_unique_eof(tool.postcontent)
    shell_cmd = "meld $(tool.file_path) <(cat <<'$delimiter'\n$(tool.postcontent)\n$delimiter\n)"
    print_code(get_shortened_code(shell_cmd, 1, 1))
    cmd_info_modify(`zsh -c $shell_cmd`)
end