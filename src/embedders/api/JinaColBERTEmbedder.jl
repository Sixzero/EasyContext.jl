using HTTP
using JSON3
using RAGTools: AbstractEmbedder, get_embeddings

struct JinaColBERTEmbedder <: AbstractEmbedder
    api_url::String
    api_key::String
end

function get_embeddings(embedder::JinaColBERTEmbedder, docs::AbstractVector{<:AbstractString};
    verbose::Bool = true,
    cost_tracker = Threads.Atomic{Float64}(0.0),
    kwargs...)

    headers = [
        "Content-Type" => "application/json",
        "Authorization" => "Bearer $(embedder.api_key)"
    ]

    embeddings = []
    
    for doc in docs
        payload = JSON3.write(Dict("texts" => [doc], "mode" => "dense"))
        
        response = HTTP.post(embedder.api_url, headers, payload)
        
        if response.status == 200
            result = JSON3.read(String(response.body))
            # Assuming the API returns a list of embeddings for each token
            doc_embeddings = result["embeddings"][1]
            push!(embeddings, doc_embeddings)
        else
            @warn "Failed to get embeddings for document: $doc"
            push!(embeddings, [])
        end
    end

    if verbose
        @info "Embedding complete for $(length(docs)) documents."
    end

    return embeddings
end

# Helper function to create a JinaColBERTEmbedder instance
function create_jina_colbert_embedder(api_url::String, api_key::String)
    JinaColBERTEmbedder(api_url, api_key)
end
