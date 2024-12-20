using HTTP
using JSON3

get_unique_eof(content::String) = occursin("EOF", content) ? "EOF_" * randstring(3) : "EOF"

@kwdef struct MeldDiffView <: AbstractDiffView end
keywords(::Type{MeldDiffView}) = ["meld"]

@kwdef struct VimDiffView <: AbstractDiffView end
keywords(::Type{VimDiffView}) = ["vimdiff", "vim"]

@kwdef struct MonacoMeldDiffView <: AbstractDiffView
    port::String = get(ENV, "MELD_PORT", "9000")
end
register_diffview_subtype!(MeldDiffView)
register_diffview_subtype!(VimDiffView)
register_diffview_subtype!(MonacoMeldDiffView)
keywords(::Type{MonacoMeldDiffView}) = ["meld-pro", "meld_pro", "monacomeld", "monaco"]

# Service availability check
is_diff_service_available(port::AbstractString) = try
    HTTP.get("http://localhost:$port/health", readtimeout=1)
    true
catch
    false
end

# Execute implementations for each view type
function execute(cmd::ModifyFileCommand, view::MeldDiffView; no_confirm=false)
    delimiter = get_unique_eof(cmd.postcontent)
    cmd_code = "meld $(cmd.file_path) <(cat <<'$delimiter'\n$(cmd.postcontent)\n$delimiter\n)"
    print_code(get_shortened_code(cmd_code, 1, 1))
    cmd_all_info_modify(`zsh -c $cmd_code`)
end

function execute(cmd::ModifyFileCommand, view::VimDiffView; no_confirm=false)
    content_esced = replace(cmd.postcontent, "'" => "\\'")
    cmd_code = "vimdiff $(cmd.file_path) <(echo -e '$content_esced')"
    print_code(get_shortened_code(cmd_code, 1, 1))
    cmd_all_info_modify(`zsh -c $cmd_code`)
end

function execute(cmd::ModifyFileCommand, view::MonacoMeldDiffView; no_confirm=false)
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
