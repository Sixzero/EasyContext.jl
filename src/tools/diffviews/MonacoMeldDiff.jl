
@kwdef struct MonacoMeldDiffView <: AbstractDiffView
  port::String = get(ENV, "MELD_PORT", "9000")
end

keywords(::Type{MonacoMeldDiffView}) = ["meld-pro", "meld_pro", "monacomeld", "monaco"]
register_diffview_subtype!(MonacoMeldDiffView)

function execute(cmd::ModifyFileTool, view::MonacoMeldDiffView; no_confirm=false)
    if is_diff_service_available(view.port)
        payload = Dict(
            "leftPath" => string(cmd.file_path),
            "rightContent" => cmd.postcontent,
            "pwd" => cmd.root_path
        )
        json_str = JSON3.write(payload)
        json_str_for_shell = replace(json_str, "'" => "'\\''")
        cmd_code = """curl -X POST http://localhost:$(view.port)/diff -H "Content-Type: application/json" -d '$(json_str_for_shell)'"""
        print_code("curl diff...")
        cmd_all_info_modify(`zsh -c $cmd_code`)
    else
        @info "No monacomeld running on: http://localhost:$(view.port)"
        # Fallback to meld
        execute(cmd, MeldDiffView(); no_confirm)
    end
end

# Service availability check
function is_diff_service_available(port::AbstractString)
  try
    HTTP.get("http://localhost:$port/health", readtimeout=1)
    true
  catch
    false
  end
end
