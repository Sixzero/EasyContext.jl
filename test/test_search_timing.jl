using Test
using EasyContext
using Base.Threads: Atomic

@testset "Search timing" begin
    chunks = ["doc1", "doc2", "doc3"]
    query = "test query"
    
    cost_tracker = Atomic{Float64}(0.0)
    time_tracker = Atomic{Float64}(0.0)
    
    rag = TwoLayerRAG(
        create_openai_embedder(),
        SimpleGPTReranker()
    )
    
    results = search(rag, chunks, query; cost_tracker, time_tracker)
    
    @test time_tracker[] > 0.0
    @test cost_tracker[] > 0.0
end
