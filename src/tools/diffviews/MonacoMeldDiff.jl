
@kwdef struct MonacoMeldDiffView <: AbstractDiffView
  port::String = get(ENV, "MELD_PORT", "9000")
end

keywords(::Type{MonacoMeldDiffView}) = ["meld-pro", "meld_pro", "monacomeld", "monaco"]
register_diffview_subtype!(MonacoMeldDiffView)

function execute(tool::ModifyFileTool, view::MonacoMeldDiffView; no_confirm=false)
    if is_diff_service_available(view.port)
        file_path, line_range = parse_source(tool.file_path)
        payload = Dict(
            "leftPath" => string(file_path),
            "rightContent" => tool.postcontent,
            "pwd" => tool.root_path
        )
        json_str = JSON3.write(payload)
        json_str_for_shell = replace(json_str, "'" => "'\\''")
        cmd_code = """curl -X POST http://localhost:$(view.port)/diff -H "Content-Type: application/json" -d '$(json_str_for_shell)'"""
        print_code("curl diff...")
        execute_with_output(`zsh -c $cmd_code`)
    else
        @info "No monacomeld running on: http://localhost:$(view.port)"
        # Fallback to meld
        execute(tool, MeldDiffView(); no_confirm)
    end
end

# Service availability check with auto-start capability
function is_diff_service_available(port::AbstractString)
  try
    HTTP.get("http://localhost:$port/health", readtimeout=1)
    return true
  catch
    # Try to start monacomeld if command exists
    try
      if success(`which monacomeld`)
        run(`bash -c "unset GTK_PATH; gnome-terminal -- bash -c 'monacomeld; exec bash'"`)
        sleep(2)  # Give it a second to start
        try
          HTTP.get("http://localhost:$port/health", readtimeout=1)
          return true
        catch
          return false
        end
      end
    catch
      return false
    end
  end
end
