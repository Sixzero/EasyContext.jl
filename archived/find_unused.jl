using RelevanceStacktrace
using MacroTools

# Function to extract all function definitions and function calls from a file
function extract_functions_and_calls(file_path)
    content = read(file_path, String)
    expr = Meta.parse("begin $content end")
    defined_functions = Dict{Symbol, String}()
    called_functions = Set{Symbol}()
    
    MacroTools.postwalk(expr) do node
        if @capture(node, function f_(args__) body__ end) || 
           @capture(node, f_(args__) = body__) ||
           @capture(node, (f_(args__) -> body__)) 
            defined_functions[Symbol(f)] = file_path
        elseif @capture(node, g_(args__)) || @capture(node, g_.(args__))  # Include broadcast calls
            push!(called_functions, Symbol(g))
        end
        node
    end
    
    return defined_functions, called_functions
end

# Main function to find unused functions
function find_unused_functions(project_path)
    all_defined_functions = Dict{Symbol, String}()
    all_called_functions = Set{Symbol}()
    julia_files = String["../AIStuff/AISH.jl/src/AISH.jl"]
    
    # Collect all Julia files, extract function definitions and calls
    FILTERED_FOLDERS =["test","archive", "archived", "playground", ".git"]
    for (root, _, files) in walkdir(project_path, topdown=true)
        any(d -> d in FILTERED_FOLDERS, splitpath(root)) && continue
        for file in files
            if endswith(file, ".jl")
                file_path = joinpath(root, file)
                push!(julia_files, file_path)
                @show file_path
                defined, called = extract_functions_and_calls(file_path)
                merge!(all_defined_functions, defined)
                union!(all_called_functions, called)
            end
        end
    end
    
    # Find unused functions
    unused_functions = Dict{Symbol, String}()
    for (func_name, defined_in) in all_defined_functions
        if func_name ∉ all_called_functions
            unused_functions[func_name] = defined_in
        end
    end
    
    return unused_functions
end

# Run the script
project_path = "."  # Assumes the script is run from the project root
unused_functions = find_unused_functions(project_path)

# Print results
if isempty(unused_functions)
    println("No unused functions found.")
else
    println("Potentially unused functions:")
    for (func_name, file_path) in unused_functions
        println("$func_name in $file_path")
    end
    @show length(unused_functions)
end
