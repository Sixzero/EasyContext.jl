import PromptingTools.Experimental.RAGTools: get_chunks, AbstractEmbedder
import PromptingTools.Experimental.RAGTools: find_tags, get_embeddings, ChunkEmbeddingsIndex, AbstractChunkIndex, find_tags
import PromptingTools.Experimental.RAGTools: ChunkIndex, AbstractChunker
import ExpressionExplorer

# TODO: add coverage info to guide test generation
# generate coverage, extract from coverage (same locations), remove coverage
@kwdef struct SourceChunk
  name::Symbol
  signature_hash::Union{UInt64,Nothing} = nothing
  # all symbols in the function body
  references::Vector{Symbol} = Symbol[]
  start_line_code::Int
  end_line_code::Int
  start_line_docs::Int = 0
  end_line_docs::Int = 0
  file_path::String
  is_function::Bool = false
  chunk::Union{String,Nothing} = nothing
end
struct SourceChunker <: AbstractChunker end

file_path_lineno(def::SourceChunk) = "$(def.file_path):$(def.start_line_code)"
file_path(def::SourceChunk) = def.file_path
name_with_signature(def::SourceChunk) = "$(def.name):$(def.signature_hash)"

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
        expr = Expr(:block, expr.args[2].args[3], expr.args[2].args[4].args[3].args...)
        while last_line > 0 && !startswith(strip(lines[last_line]), "end")
            last_line -= 1
        end
        last_line -= 1 # "end" line
    end
    expr, last_line
end
function source_explorer(expr_tree, lines::AbstractVector{<:AbstractString};
    file_path::AbstractString, last_line::Int=length(lines), source_defs=SourceChunk[], module_name="")

    # Handle toplevel and module expressions # hacky way. if toplevel holds a module, then it will be in args[2]
    #   @show expr_tree.args[2].args[4]
    expr_tree, last_line = handle_single_module_file(expr_tree, last_line, lines)
    expr_tree, last_line = handle_docstring_file(expr_tree, last_line, lines)
    
    current_line = 1
    for i in eachindex(expr_tree.args)
        expr = expr_tree.args[i]
    #   @show expr
        if expr isa LineNumberNode
            current_line = expr.line
            continue
        end
        # @show current_line
        # @show expr
        if isa(expr, Expr) && expr.head == :module
            new_lastline = last_line
            while new_lastline > 0 && !startswith(strip(lines[new_lastline]), "end")
                new_lastline -= 1
            end
            new_lastline -= 1 # "end" line
            @show new_lastline
            source_explorer(expr.args[3], lines; file_path, source_defs, last_line=new_lastline)
            continue
        end
        ## code position
        start_line_code = current_line
        next_expr_index = findnext(x -> x isa LineNumberNode, expr_tree.args, i + 1)
        end_line_code = !isnothing(next_expr_index) ? expr_tree.args[next_expr_index].line - 1 : last_line
        # @show start_line_code, next_expr_index, end_line_code
        end_line_code = max(end_line_code, current_line)
        ## grab the first non-empty before that
        while empty_line(lines[end_line_code])
            end_line_code == start_line_code && break
            end_line_code -= 1
        end

        ## skip if not expression
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

        ## defaults
        name, signature_hash = :unknown, nothing
        is_function = false
        references = Symbol[]
        if expr.head == :function || ExpressionExplorer.is_function_assignment(expr)
            ## quick and dirty parser
            r = ExpressionExplorer.compute_reactive_node(expr)
            references = r.references |> collect
            ## just grab the first function def, ignore the rest
            name, signature_hash = if !isempty(r.funcdefs_with_signatures)
                out = first(r.funcdefs_with_signatures)
                out.name.joined, out.signature_hash
            elseif !isempty(r.funcdefs_without_signatures)
                out = first(r.funcdefs_without_signatures)
                out, nothing
            else
                :unknown, nothing
            end
            is_function = true
        elseif expr.head == :macrocall && !isempty(expr.args) &&
                (expr.args[1] == Symbol("@kwdef") ||
                (expr.args[1] isa Expr && !isempty(expr.args[1].args) &&
                expr.args[1].args[end] == Symbol("@kwdef")))
            ## @kwdef or Base.@kwdef
            if length(expr.args) >= 3 && expr.args[3] isa Expr
                r = ExpressionExplorer.compute_reactive_node(expr.args[3])
                references = r.references |> collect
                name, signature_hash = if !isempty(r.funcdefs_with_signatures)
                    out = first(r.funcdefs_with_signatures)
                    out.name.joined, out.signature_hash
                elseif !isempty(r.funcdefs_without_signatures)
                    out = first(r.funcdefs_without_signatures)
                    out, nothing
                else
                    :unknown, nothing
                end
            else
                @warn "Unknown expression type: $(expr.head) & $(expr.args[1])"
            end
        elseif expr.head == :macrocall && !isempty(expr.args) &&
                expr.args[1] == Symbol("@enum")
            ## @enum
            if length(expr.args) >= 3
                name = Symbol("$(expr.args[3])") # @enum OpCode::UInt8 was not a Symbol so this hacky way converts it again to Symbol
                # We are not using references anymore.
                references = Symbol[] # expr.args[min(length(expr.args), 4):end]
            else
                @warn "Unknown expression type: $(expr.head) & $(expr.args[1])"
            end
        elseif expr.head == :macrocall && !isempty(expr.args) &&
                expr.args[1] == GlobalRef(Core, Symbol("@doc"))
            # expr.args[4].args[3] = docstring // args[4] the function def
            if length(expr.args) >= 4 && expr.args[4] isa Expr
                r = ExpressionExplorer.compute_reactive_node(expr.args[4])
                references = r.references |> collect
                ## start_line_docs = current_line
                ## end_line_docs = start_line_docs + count(==('\n'), expr.args[4].args[3])
                name, signature_hash = if !isempty(r.funcdefs_with_signatures)
                    out = first(r.funcdefs_with_signatures)
                    out.name.joined, out.signature_hash
                elseif !isempty(r.funcdefs_without_signatures)
                    out = first(r.funcdefs_without_signatures)
                    out, nothing
                else
                    :unknown, nothing
                end
                ## is it a function?
                if expr.args[4].head == :function ||
                    ExpressionExplorer.is_function_assignment(expr.args[4])
                    is_function = true
                end
            else
                @warn "Unknown expression type: $(expr.head) & $(expr.args[1])"
            end
        else
            ## quick and dirty fallback parser
            r = ExpressionExplorer.compute_reactive_node(expr)
            references = r.references |> collect
            ## just grab the first function def, ignore the rest
            name, signature_hash = if !isempty(r.funcdefs_with_signatures)
                out = first(r.funcdefs_with_signatures)
                out.name.joined, out.signature_hash
            elseif !isempty(r.funcdefs_without_signatures)
                out = first(r.funcdefs_without_signatures)
                out, nothing
            else
                :unknown, nothing
            end
            ## if a type definition, grab the name from definitions
            if name == :unknown && !isempty(r.definitions)
                name = first(r.definitions)
            end
        end
        # @show name, signature_hash
        len = end_line_code - start_line_code
        chunk = join(lines[start_line_code:start_line_code+len], '\n')
        chunk = length(chunk) > 14000 ? "$(chunk[1:12000])\n ... \n$(lines[start_line_code+len])" : chunk 
        #   @show chunk
        def = SourceChunk(; name, signature_hash, references, is_function,
            start_line_code, end_line_code, file_path, chunk)
        
        @assert (len < 600 || (len ∈ [1224, 667, 761])) "We have a too long context $(end_line_code - start_line_code) probably for head: $(expr.head) in $(expr_tree.head) file_path: $(file_path):$(start_line_code)"
        push!(source_defs, def)
    end

  return source_defs
end

function process_jl_file(file_path, verbose::Bool=true)
    verbose && @info "Processing file: $file_path"
    s = read(file_path, String)
    lines = split(s, '\n')
    expr = Meta.parseall(s)
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
          append!(definitions, defs)
      end
  end
  return definitions
end
function get_chunks(chunker::SourceChunker,
        files_or_docs::Vector{<:AbstractString};
        sources::AbstractVector{<:AbstractString} = files_or_docs,
        verbose::Bool = true,)

    ## Check that all items must be existing files or strings
    @assert (length(sources)==length(files_or_docs)) "Length of `sources` must match length of `files_or_docs`"

    output_chunks = Vector{SubString{String}}()
    output_sources = Vector{eltype(sources)}()

    # Do chunking first
    for i in eachindex(files_or_docs, sources)
      defs = process_source_directory(files_or_docs[i])
      chunks = ["$(def.file_path):$(def.start_line_code)\n" *  def.chunk for def in defs]

      @assert all(!isempty, chunks) "Chunks must not be empty. The following are empty: $(findall(isempty, chunks))"
    
      sources = file_path_lineno.(defs)
      append!(output_chunks, chunks)
      append!(output_sources, sources)
    end

    return output_chunks, output_sources
end