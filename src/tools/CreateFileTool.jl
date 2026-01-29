using ToolCallFormat: Context as ToolContext
# @deftool, CodeBlock imported via ToolInterface.jl

@deftool "Create a new file with content" function create_file(file_path::String, content::CodeBlock; ctx::ToolContext)
    # Clean file_path (remove trailing >)
    file_path = endswith(file_path, ">") ? chop(file_path) : file_path
    path = expand_path(file_path, ctx.root_path)

    shell_cmd = process_create_command(path, string(content))
    shortened_code = get_shortened_code(shell_cmd, 4, 2)
    print_code(shortened_code)

    dir = dirname(path)
    !isdir(dir) && mkpath(dir)

    no_confirm = get(kw, :no_confirm, false)
    if no_confirm || get_user_confirmation()
        print_output_header()
        execute_with_output(`zsh -c $shell_cmd`)
    else
        "\nOperation cancelled by user."
    end
end

#==============================================================================#
# Helper functions
#==============================================================================#

function process_create_command(file_path::String, content::String)
    delimiter = get_unique_eof(content)
    escaped_path = replace(file_path, r"[\[\]()]" => s"\\\0")
    "cat > $(escaped_path) <<'$delimiter'\n$(content)\n$delimiter"
end
