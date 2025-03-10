using Test
using EasyContext
using EasyContext: EFFICIENT_PIPELINE, HIGH_ACCURACY_PIPELINE

@testset "RAG Pipeline Configurations" begin
    # Test EFFICIENT_PIPELINE with default parameters
    efficient = EFFICIENT_PIPELINE()
    @test efficient isa TwoLayerRAG
    @test efficient.topK.top_k == 50
    @test efficient.reranker isa ReduceGPTReranker
    @test efficient.reranker.top_n == 10
    @test efficient.reranker.model == ["gem20f", "gem15f", "orqwenplus"]
    
    # Test EFFICIENT_PIPELINE with custom parameters
    efficient_custom = EFFICIENT_PIPELINE(top_n=15, cache_prefix="custom")
    @test efficient_custom.reranker.top_n == 15
    
    # Test HIGH_ACCURACY_PIPELINE
    accurate = HIGH_ACCURACY_PIPELINE()
    @test accurate isa TwoLayerRAG
    @test accurate.topK.top_k == 120
    @test accurate.reranker isa ReduceGPTReranker
    @test accurate.reranker.top_n == 12
    @test accurate.reranker.model == "gpt4om"
    
    # Test custom parameters in init_workspace_context
    dummy_paths = ["."]
    ctx1 = init_workspace_context(dummy_paths)
    @test ctx1.rag_pipeline.topK.top_k == 50
    
    ctx2 = init_workspace_context(dummy_paths; pipeline=HIGH_ACCURACY_PIPELINE())
    @test ctx2.rag_pipeline.topK.top_k == 120
    
    # Test init_julia_context
    julia_ctx = init_julia_context()
    @test julia_ctx.rag_pipeline.topK.top_k == 50
    @test julia_ctx.rag_pipeline.reranker.top_n == 10
    
    # Test init_julia_context with custom pipeline
    julia_ctx2 = init_julia_context(pipeline=HIGH_ACCURACY_PIPELINE(cache_prefix="juliapkgs"))
    @test julia_ctx2.rag_pipeline.topK.top_k == 120
    @test julia_ctx2.rag_pipeline.reranker.top_n == 12
end
