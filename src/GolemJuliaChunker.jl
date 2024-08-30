import PromptingTools.Experimental.RAGTools: AbstractEmbedder
import PromptingTools.Experimental.RAGTools: find_tags, get_embeddings, ChunkEmbeddingsIndex, AbstractChunkIndex, find_tags
import PromptingTools.Experimental.RAGTools: ChunkIndex, AbstractChunker
import ExpressionExplorer
import PromptingTools
using JuliaSyntax
const RAG = PromptingTools.Experimental.RAGTools

@kwdef struct JuliaSourceChunk
  name::Symbol
  signature_hash::Union{UInt64,Nothing} = nothing
  references::Vector{Symbol} = Symbol[]
  start_line_code::Int
  end_line_code::Int
  start_line_docs::Int = 0
  end_line_docs::Int = 0
  file_path::String
  is_function::Bool = false
  chunk::Union{String,Nothing} = nothing
end

struct JuliaSourceChunker <: AbstractChunker end

file_path_lineno(def::JuliaSourceChunk) = "$(def.file_path):$(def.start_line_code)"
file_path(def::JuliaSourceChunk) = def.file_path
name_with_signature(def::JuliaSourceChunk) = "$(def.name):$(def.signature_hash)"

# Include the existing Julia-specific functions from GolemSourceChunks.jl here
# Such as empty_line, handle_single_module_file, handle_docstring_file, get_last_line_number, source_explorer, etc.

function RAG.get_chunks(chunker::JuliaSourceChunker,
        files_or_docs::Vector{<:AbstractString};
        sources::AbstractVector{<:AbstractString} = files_or_docs,
        verbose::Bool = true,)

    @assert (length(sources)==length(files_or_docs)) "Length of `sources` must match length of `files_or_docs`"

    output_chunks = Vector{SubString{String}}()
    output_sources = Vector{eltype(sources)}()

    for i in eachindex(files_or_docs, sources)
      defs = process_jl_file(files_or_docs[i], verbose)
      chunks = ["$(def.file_path):$(def.start_line_code)\n" *  def.chunk for def in defs]

      @assert all(!isempty, chunks) "Chunks must not be empty. The following are empty: $(findall(isempty, chunks))"
    
      sources = file_path_lineno.(defs)
      append!(output_chunks, chunks)
      append!(output_sources, sources)
    end

    return output_chunks, output_sources
end

# Include the process_jl_file and process_source_directory functions here
function process_jl_file(file_path, verbose::Bool=true)
  verbose && @info "Processing file: $file_path"
  s = read(file_path, String)
  # @time expr2 = parsestmt(JuliaSyntax.SyntaxNode, "begin\n"*s*"\nend", filename=file_path)
  # @show typeof(expr2)
  expr = Meta.parseall(s)       
  lines = split(s, '\n')
  defs = source_explorer(expr, lines; file_path)
  defs
end

function process_source_directory(dir::AbstractString; verbose::Bool=true)
  dir = expanduser(dir)
  @assert isdir(dir) "Directory does not exist: $dir"
  definitions = SourceChunk[]
  for (dir, _, files) in walkdir(dir)
      for file in files
          ## only Julia files
          if !endswith(file, ".jl")
              continue
          end
          file_path = joinpath(dir, file)
          defs = process_jl_file(file_path, verbose)
        #   @assert length(definitions)<30
          append!(definitions, defs)
      end
  end
  return definitions
end

function empty_line(line::AbstractString)
  stripped = strip(line)
  return isempty(stripped) || startswith(stripped, "#")
end

## Meta.parseall(read("/Users/simljx/Documents/PromptingTools/src/precompilation.jl", String))

function handle_single_module_file(expr, last_line, lines)
    if expr.head == :toplevel && length(expr.args) == 2 && expr.args[2].head == :module
        @info "We unwrap toplevel and module"
        expr = expr.args[2].args[3] # unwrap toplevel
        module_name = expr.args[2]
    end
    expr, last_line
end 
""" ugly. it got developed based on what issue we came accross, this function fullfills the tests, but basically it unwraps the module behind the docstring."""
function handle_docstring_file(expr, last_line, lines)
    if expr.head == :toplevel && length(expr.args) >= 2 && expr.args[2] isa Expr && expr.args[2].head == :macrocall && expr.args[2].args[1] isa GlobalRef && expr.args[2].args[1].name == Symbol("@doc") && expr.args[2].args[4] isa Expr && expr.args[2].args[4].head == :module
        @info "We unwrap docstring file"
        # @show expr.args[2].args[3]
        # @show expr.args[2].args[4].args[2]
        # @show expr.args[2].args[4].args[3].head
        # @show length(expr.args[2].args[4].args[3].args)
        module_name = expr.args[2].args[4].args[2]
        # new_lastline = get_last_line_number(expr.args[2].args[4].args[3]) 
        expr = Expr(:block, expr.args[2].args[3], expr.args[2].args[4].args[3].args...)
        while last_line > 0 && !startswith(strip(lines[last_line]), "end")
            last_line -= 1
        end
        last_line -= 1 # "end" line
        # @show new_lastline,  last_line
        # @assert new_lastline == last_line "Newlines not equal $new_lastline != $last_line The lines:\n$(lines[new_lastline]) $(lines[last_line])\n"
    end
    expr, last_line
end

function get_last_line_number(expr::Expr)
    last_line = nothing
    for arg in Iterators.reverse(expr.args)
        if isa(arg, LineNumberNode)
            return arg.line + (expr.head == :block ? 1 : 0)
        elseif isa(arg, Expr)
            last_line = get_last_line_number(arg)
            if last_line !== nothing
                return last_line + (expr.head == :block ? 1 : 0)
            end
        end
    end
    return nothing
end
get_last_line_number(expr::LineNumberNode) = expr.line
function source_explorer(expr_tree, lines::AbstractVector{<:AbstractString};
    file_path::AbstractString, last_line::Int=length(lines), source_defs=SourceChunk[], module_name="")

    expr_tree, last_line = handle_single_module_file(expr_tree, last_line, lines)
    expr_tree, last_line = handle_docstring_file(expr_tree, last_line, lines)
    
    current_line = 1
    for i in eachindex(expr_tree.args)
        expr = expr_tree.args[i]
        if expr isa LineNumberNode
            current_line = expr.line
            continue
        end
        if isa(expr, Expr) && expr.head == :module
            new_lastline = get_last_line_number(expr.args[3]) + 1
            @show new_lastline
            source_explorer(expr.args[3], lines; file_path, source_defs, last_line=new_lastline)
            continue
        end
        
        start_line_code = current_line
        next_expr_index = findnext(x -> x isa LineNumberNode, expr_tree.args, i + 1)
        end_line_code = !isnothing(next_expr_index) ? expr_tree.args[next_expr_index].line - 1 : last_line
        end_line_code = max(end_line_code, current_line)
        
        while empty_line(lines[end_line_code])
            end_line_code == start_line_code && break
            end_line_code -= 1
        end

        if !isa(expr, Expr)
            if isa(expr, String)
                signature_hash = hash(expr)
                chunk = join(lines[(start_line_code):(end_line_code)], '\n')
                def = SourceChunk(; name=:Documentation, signature_hash, references=Symbol[], is_function=false, start_line_code, end_line_code, file_path, chunk)
                push!(source_defs, def)
                continue
            end
            @warn "Unknown type: $(typeof(expr))"
            continue
        end

        name::Symbol, signature_hash = :unknown, nothing
        is_function = false
        references = Symbol[]
        
        if expr.head == :function || is_function_assignment(expr)
            name = get_function_name(expr)
            signature_hash = hash(string(expr))
            is_function = true
        elseif expr.head == :macrocall && !isempty(expr.args)
            if expr.args[1] == Symbol("@kwdef") || (expr.args[1] isa Expr && !isempty(expr.args[1].args) && expr.args[1].args[end] == Symbol("@kwdef"))
                if length(expr.args) >= 3 && expr.args[3] isa Expr
                    name = get_struct_name(expr.args[3])
                    signature_hash = hash(string(expr.args[3]))
                else
                    @warn "Unknown expression type: $(expr.head) & $(expr.args[1])"
                end
            elseif expr.args[1] == Symbol("@enum")
                if length(expr.args) >= 3
                    name = Symbol("$(expr.args[3])")
                    references = Symbol[]
                else
                    @warn "Unknown expression type: $(expr.head) & $(expr.args[1])"
                end
            elseif expr.args[1] == GlobalRef(Core, Symbol("@doc"))
                if length(expr.args) >= 4 && expr.args[4] isa Expr
                    name = get_function_name(expr.args[4])
                    signature_hash = hash(string(expr.args[4]))
                    if expr.args[4].head == :function || is_function_assignment(expr.args[4])
                        is_function = true
                    end
                else
                    @warn "Unknown expression type: $(expr.head) & $(expr.args[1])"
                end
            end
        else
            name = get_expression_name(expr)
            signature_hash = hash(string(expr))
        end
        
        len = end_line_code - start_line_code
        chunk = join(lines[start_line_code:start_line_code+len], '\n')

        if length(chunk) > 14000
            first_part = safe_substring(chunk, 1, 12000)
            chunk = "$first_part\n ... \n$(lines[start_line_code+len])"
        end
        
        def = SourceChunk(; name, signature_hash, is_function,
            start_line_code, end_line_code, file_path, chunk)
        
        @assert (len < 600 || (len ∈ [1224, 667, 761, 918, 1186, 2542, 1765])) "We have a too long context $(end_line_code - start_line_code) probably for head: $(expr.head) in $(expr_tree.head) file_path: $(file_path):$(start_line_code)"
        push!(source_defs, def)
    end

    return source_defs
end

# is there an alternative to unicode safe indexing?
function safe_substring(s, from, to)
    start = firstindex(s)
    stop = lastindex(s)
    
    from_index = min(max(start, from), stop)
    to_index = min(max(from_index, to), stop)
    
    from_index = nextind(s, from_index - 1)
    to_index = prevind(s, to_index + 1)
    
    return s[from_index:to_index]
end