
@kwdef struct MeldDiffView <: AbstractDiffView end
keywords(::Type{MeldDiffView}) = ["meld"]

register_diffview_subtype!(MeldDiffView)

# Execute implementations for each view type
function execute(cmd::ModifyFileTool, view::MeldDiffView; no_confirm=false)
  delimiter = get_unique_eof(cmd.postcontent)
  cmd_code = "meld $(cmd.file_path) <(cat <<'$delimiter'\n$(cmd.postcontent)\n$delimiter\n)"
  print_code(get_shortened_code(cmd_code, 1, 1))
  cmd_all_info_modify(`zsh -c $cmd_code`)
end