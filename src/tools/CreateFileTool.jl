# @deftool, TextBlock imported via ToolInterface.jl

@deftool "Create a new file with content" (
    root_path::Union{Nothing,String} = nothing,
    no_confirm::Bool = false,
) function local_create_file(path::String, content::TextBlock)
    # Clean path (remove trailing >)
    path = endswith(path, ">") ? chop(path) : path
    path = expand_path(path, root_path)

    shell_cmd = process_create_command(path, content)
    shortened_code = get_shortened_code(shell_cmd, 4, 2)
    print_code(shortened_code)

    dir = dirname(path)
    !isdir(dir) && mkpath(dir)

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
