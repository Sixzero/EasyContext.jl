using PromptingTools.Experimental.RAGTools

@kwdef struct PythonPkgInfo
    name::String
    version::String
    location::String
end

@kwdef mutable struct PythonLoader <: AbstractLoader
    package_scope::Symbol = :installed  # :installed, :dependencies, or :all
    index_builder::Nothing = nothing # # TODO remove the need for this, index is not its responsibility, I think only returning the chunks should be.
    packages::Vector{PythonPkgInfo} = PythonPkgInfo[]
end

function get_context(context::PythonLoader, question::String, ai_state=nothing, shell_results=nothing)
    pkg_infos = get_python_package_infos(context.packages)
    result = get_context(context.index_builder, question; data=pkg_infos)
    return  Dict(result.sources .=> result.context)
end

function get_python_package_infos(packages::Vector{PythonPkgInfo})
    return [
        "Name: $(pkg.name)\n" *
        "Version: $(pkg.version)\n" *
        "Location: $(pkg.location)\n" *
        "Description: $(get_package_description(pkg.name))"
        for pkg in packages
    ]
end

function get_package_description(package_name::String)
    cmd = `pip show $(package_name)`
    output = try
        read(cmd, String)
    catch
        return "Description not available"
    end
    
    for line in split(output, '\n')
        if startswith(line, "Summary: ")
            return strip(replace(line, "Summary: " => ""))
        end
    end
    
    return "Description not available"
end


# Helper function to find Python packages
function find_python_packages()
    cmd = `pip list --format=json`
    output = read(cmd, String)
    packages = JSON.parse(output)
    
    return [PythonPkgInfo(
        name=pkg["name"],
        version=pkg["version"],
        location=get(pkg, "location", "")
    ) for pkg in packages]
end

# Implementation of build_index for PythonPkgInfo
function RAGTools.build_index(
    indexer::Union{RAGTools.SimpleIndexer, RAGTools.KeywordsIndexer},
    files_or_docs::Vector{PythonPkgInfo};
    verbose::Integer = 1,
    extras::Union{Nothing, AbstractVector} = nothing,
    index_id = gensym("PythonPackageIndex"),
    chunker = indexer.chunker,
    chunker_kwargs::NamedTuple = NamedTuple(),
    embedder = indexer isa RAGTools.SimpleIndexer ? indexer.embedder : indexer.processor,
    embedder_kwargs::NamedTuple = NamedTuple(),
    tagger = indexer.tagger,
    tagger_kwargs::NamedTuple = NamedTuple(),
    api_kwargs::NamedTuple = NamedTuple(),
    cost_tracker = Threads.Atomic{Float64}(0.0)
)
    # Convert PythonPkgInfo to strings
    pkg_strings = get_python_package_infos(files_or_docs)

    # Split into chunks
    chunks, sources = RAGTools.get_chunks(chunker, pkg_strings; sources=pkg_strings, chunker_kwargs...)

    if indexer isa RAGTools.SimpleIndexer
        # Embed chunks
        embeddings = RAGTools.get_embeddings(embedder, chunks;
            verbose = (verbose > 1),
            cost_tracker,
            api_kwargs, embedder_kwargs...)

        # Extract tags
        tags_extracted = RAGTools.get_tags(tagger, chunks;
            verbose = (verbose > 1),
            cost_tracker,
            api_kwargs, tagger_kwargs...)
        # Build the sparse matrix and the vocabulary
        tags, tags_vocab = RAGTools.build_tags(tagger, tags_extracted)

        (verbose > 0) && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"

        index = RAGTools.ChunkEmbeddingsIndex(; id = index_id, embeddings, tags, tags_vocab,
            chunks, sources, extras)
    else
        # Tokenize and DTM
        dtm = RAGTools.get_keywords(embedder, chunks;
            verbose = (verbose > 1),
            cost_tracker,
            api_kwargs, embedder_kwargs...)

        # Extract tags
        tags_extracted = RAGTools.get_tags(tagger, chunks;
            verbose = (verbose > 1),
            cost_tracker,
            api_kwargs, tagger_kwargs...)
        # Build the sparse matrix and the vocabulary
        tags, tags_vocab = RAGTools.build_tags(tagger, tags_extracted)

        (verbose > 0) && @info "Index built! (cost: \$$(round(cost_tracker[], digits=3)))"

        index = RAGTools.ChunkKeywordsIndex(; id = index_id, chunkdata = dtm, tags, tags_vocab,
            chunks, sources, extras)
    end

    return index
end
