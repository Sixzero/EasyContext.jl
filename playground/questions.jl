using EasyContext: get_answer, get_context, JuliaPackageContext, format_context_node, CodebaseContextV2
using EasyContext: BM25IndexBuilder, JinaEmbeddingIndexBuilder, EmbeddingIndexBuilder, MultiIndexBuilder, ContextNode
import EasyContext: get_context, RAGContext, ReduceRankGPTReranker
using PromptingTools: pprint
# question = "I need to walk packages. I also want to track whether I could trace in a stack which modules I am in currently."
question = "How to use BM25 for retrieval?"
question = "How do we add KVCache ephemeral cache for anthropic claude ai request?"
question = "How can we use DiffLib library in julia for reconstructing a 3rd file from 2 file?"
question = "Maybe we coul introduce the Chunk struct which would hold context and source and extra fields?"
question = "I would want you to use ReplMaker.jl to create a terminal for AI chat. Which would basically be the improved_readline for AISH.jl "
# question = "How can we use DiffLib module in julia for reconstructing a 3rd file from 2 file?"
# question = "What does DiffLib library/module do?"
# question = "How can we use DiffLib.jl library in julia for reconstructing a 3rd file from 2 file?"
# question = "Could we create a file which would use jina or voyage or some ColBERT type multi vector embedding solution?"
# question = "What is in ChunkEmbeddingIndex the .id is used for?"
# question = "How do I process the chunks into keywords for BM25?"
# question = "I need to walk packages like in PkgManager. I also want to track whether I could trace in a stack which modules I am in currently."
# question = "I need to walk packages line by line like in PkgManager. I also want to track whether I could trace in a stack which modules I am in currently."
# msg = get_context(question, force_rebuild=false)
# msg = get_answer(question, )
# pprint(msg)
aistate_mock = (conversations=[(;messages=String[], rel_project_paths=".")], selected_conv_id=1, )
ctxer = JuliaPackageContext() 
# ctxer = JuliaPackageContext() * MultiIndexBuilder(;builders=[BM25IndexBuilder()], top_k=100) * rerank(CohereReranker(), top_n=10) * ContextNode(docs="Functions", doc="Function")
ctxer = [
    JuliaPackageContext(),
    EmbeddingIndexBuilder(), 
    # MultiIndexBuilder(;builders=[
    #     EmbeddingIndexBuilder(),
    #     # JinaEmbeddingIndexBuilder(),
    #     # BM25IndexBuilder(),
    # ]),
    ReduceRankGPTReranker(),
    ContextNode(),
]
function get_context(ctx_creators::Vector, question, aistate, shell)
    # call one after the other.
    res = question
    for ctx_creator in ctx_creators
        res = ctx_creator(res)
    end
    res
end
# ctxer = CodebaseContextV2()

# for b in ctxer.index_context.index_builder.builders
#     b.force_rebuild = true
# end
question = "I would want you to use ReplMaker.jl to create a terminal for AI chat.  "
question = "I want to correct the cut_history."
question = "Now I need you to create a julia script which could use ai to generate a new file from the input file path and the corresponding .patch file. probably the original input file path could be deducted from the diff, based on what is in the diff, what file it should modify.
"
question = "Could you please implement me with ReplMaker or ReplMaker.jl an AI chat? The basic point would be what currently the improved_readline gives back in the loop, it should be done by this ReplMaker thing."
@time msg = get_context(ctxer, question, aistate_mock)
# @time msg = get_context(ctxer, question, aistate_mock)
# println(format_context_node(msg))
# println(join(msg.new_sources, '\n'))
# @time msg = get_context_embedding(question; force_rebuild=false)
# pprint(msg)
# @time msg = get_context_bm25(question; force_rebuild=false)
# pprint(msg)
;
#%%
println(msg)
#%%
using EasyContext: JinaEmbedder, get_embeddings
using Boilerplate
    qqs = [question for i  in 1:4000]
    @show length.(qqs)
    res = get_embeddings(JinaEmbedder(), qqs)

    @sizes res
#%%
using EasyContext: get_finder

map(get_finder, ctxer.index_builder.builders)
#%%
using EasyContext: JuliaPackageContext, BM25IndexBuilder, build_index, JinaEmbedder, JinaEmbeddingIndexBuilder, EmbeddingIndexBuilder
ctxer = JuliaPackageContext(;index_builder=JinaEmbeddingIndexBuilder(embedder=JinaEmbedder(
    model="jina-embeddings-v2-base-code",
)))
# ctxer = JuliaPackageContext(;index_builder=EmbeddingIndexBuilder())
using EasyContext: get_package_infos
pkg_infos = get_package_infos(:installed)
pkg_infos = pkg_infos[1:5]
index = build_index(ctxer.index_builder, pkg_infos, force_rebuild=true)
#%%
reduce(hcat,[randn(20,2), randn(20,3)])
#%%
using EasyContext: GoogleContext, get_context, CodebaseContext, JuliaPackageContext

question = "Could we create a file which would use jina or voyage or some ColBERT type multi vector embedding solution?"
question = "Could we create a file which would use jina or voyage or some ColBERT type embedder for code embedding?"
question = "Hogyan csináljak alkalmazást, miyen nyelven ajánlanéd?"
question = """ERROR: LoadError: MethodError: no method matching lastindex(::Base.KeySet{String, Dict{String, String}})

Closest candidates are:
  lastindex(::Any, ::Any)"""
question = "What packages could I use for BM25 implementation?"

ctxer = CodebaseContext()
ctxer = GoogleContext()
ctxer = JuliaPackageContext()
res = get_context(ctxer, question, nothing, nothing)
println(res);
