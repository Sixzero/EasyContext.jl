using PromptingTools
using PromptingTools.Experimental.RAGTools: extract_ranking, AbstractReranker
using Base.Threads
using DataStructures: OrderedDict
const RAG = RAGTools
const PT = PromptingTools

Base.@kwdef struct SimpleGPTReranker <: AbstractReranker 
    model::AbstractString="dscode"
    temperature::Float64=0.0
    verbose::Int=1
end

function rerank(
    reranker::SimpleGPTReranker,
    chunks::Vector{T},
    query::AbstractString;
    cost_tracker = Threads.Atomic{Float64}(0.0),
    time_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Int = reranker.verbose,
    ai_fn::Function = airatelimited
) where T
    contents = string.(chunks)  # Convert to strings if needed
    
    prompt = """
    <instruction>
    Analyze the documents and identify which ones are relevant to the question.
    Return ONLY the document IDs that are relevant as a comma-separated list.
    Return an empty list [] if no documents are relevant.
    Only use document IDs between 1 and $(length(contents)).
    
    Relevance Criteria:
    - Documents that directly answer or address the question
    - Documents containing functions or code needed for the solution
    - Documents with implementation details related to the question
    </instruction>
    
    <documents>
    $(join(["<doc id=\"$i\">\n$doc\n</doc>" for (i, doc) in enumerate(contents)], "\n"))
    </documents>
    
    <question>
    $query
    </question>
    
    <output_format>
    [Rankings, comma-separated list of document ids]
    </output_format>"""
    
    response = ai_fn(prompt; model=reranker.model, api_kwargs=(;temperature=reranker.temperature), cost_tracker)
    rankings = extract_ranking(response.content)
    
    if isempty(rankings) || !all(1 .<= rankings .<= length(contents))
        @warn "Invalid or empty rankings returned"
        return T[]
    end
    
    if verbose > 0
        println("SimpleGPT selected $(length(rankings)) documents. Cost: \$$(round(cost_tracker[], digits=4))")
    end
    
    return chunks[rankings]
end

function RAG.rerank(
    reranker::SimpleGPTReranker,
    index::AbstractDocumentIndex,
    question::AbstractString,
    candidates::AbstractCandidateChunks;
    cost_tracker = Threads.Atomic{Float64}(0.0),
    verbose::Bool = reranker.verbose,
    kwargs...
)
    documents = index[candidates, :chunks]
    sources = index[candidates, :sources]
    reranked = rerank(reranker, OrderedDict(zip(sources, documents)), question; cost_tracker, verbose)
    
    reranked_positions = findall(s -> haskey(reranked, s), sources)
    reranked_scores = ones(length(reranked_positions))
    
    if candidates isa MultiCandidateChunks
        reranked_ids = [candidates.index_ids[i] for i in reranked_positions]
        return MultiCandidateChunks(reranked_ids, reranked_positions, reranked_scores)
    else
        return CandidateChunks(candidates.index_id, reranked_positions, reranked_scores)
    end
end

function humanize(reranker::SimpleGPTReranker)
    "SimpleGPT(model=$(reranker.model))"
end
