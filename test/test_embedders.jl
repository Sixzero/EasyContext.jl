using Test
using EasyContext
using DataStructures: OrderedDict
using EasyContext: EmbedderSearch, OpenAIBatchEmbedder, CachedBatchEmbedder, JinaEmbedder, VoyageEmbedder, CombinedIndexBuilder
using EasyContext: BM25Embedder
using EasyContext: get_index
using HTTP
using PromptingTools.Experimental.RAGTools
using JSON3
using Chairmarks
using BenchmarkTools

@testset "Embedder Tests" begin
    @testset "EmbedderSearch" begin
        @testset "Constructor" begin
            builder = EmbedderSearch()
            @test builder isa EmbedderSearch
            @test builder.embedder isa CachedBatchEmbedder
            @test builder.embedder.embedder isa OpenAIBatchEmbedder
            @test builder.top_k == 300
            @test builder.force_rebuild == false
        end

        @testset "get_index" begin
            builder = EmbedderSearch()
            chunks = OrderedDict("file1.jl" => "content1", "file2.jl" => "content2")

            index = EasyContext.get_index(builder, chunks)
            @test index isa RAGTools.ChunkEmbeddingsIndex
            @test length(index.chunks) == 2
            @test length(index.sources) == 2
            @test size(index.embeddings, 2) == 2
        end

        @testset "call method" begin
            builder = EmbedderSearch(top_k=2)
            chunks = OrderedDict("file1.jl" => "content1", "file2.jl" => "content2", "file3.jl" => "content3")
            query = "test query"
            index = get_index(builder, chunks)
            result = builder(index, query)
            @test result isa OrderedDict{String, String}
            @test length(result) == 2  # top_k is 2
            @test all(k -> k in keys(chunks), keys(result))
        end

        @testset "Empty input" begin
            builder = EmbedderSearch()
            empty_chunks = OrderedDict{String, String}()
            query = "test query"
            index = get_index(builder, empty_chunks)

            @test index isa RAGTools.ChunkEmbeddingsIndex
            @test isempty(index.chunks)
            @test isempty(index.sources)
            @test size(index.embeddings, 2) == 0

            result = builder(index, query)
            @test isempty(result)
            @test result isa OrderedDict{String, String}
        end
    end

    @testset "JinaEmbedder" begin
        @testset "Constructor" begin
            embedder = JinaEmbedder()
            @test embedder isa JinaEmbedder
            @test embedder.model == "jina-embeddings-v2-base-code"
            @test embedder.input_type == "document"
        end

        @testset "get_embeddings" begin
            # Mock http_post function
            function mock_http_post(url, headers, body)
                @test url == "https://api.jina.ai/v1/embeddings"
                @test headers == ["Content-Type" => "application/json", "Authorization" => "Bearer test_key"]
                
                mock_response = Dict(
                    "data" => [
                        Dict("embedding" => rand(Float32, 512)),
                        Dict("embedding" => rand(Float32, 512))
                    ]
                )
                return HTTP.Response(200, JSON3.write(mock_response))
            end

            embedder = JinaEmbedder(api_key="test_key", http_post=mock_http_post)
            docs = ["This is a test", "Another test document"]

            embeddings = get_embeddings(embedder, docs)
            @test size(embeddings, 2) == length(docs)
            @test size(embeddings, 1) == 512  # Assuming Jina returns 512-dimensional embeddings
        end
    end

    @testset "VoyageEmbedder" begin
        @testset "Constructor" begin
            embedder = VoyageEmbedder()
            @test embedder isa VoyageEmbedder
            @test embedder.model == "voyage-code-2"
            @test isnothing(embedder.input_type)
            @test embedder.http_post == HTTP.post
        end

        @testset "get_embeddings" begin
            # Mock HTTP.post function
            function mock_http_post(url, headers, body)
                @test url == "https://api.voyageai.com/v1/embeddings"
                @test headers == ["Content-Type" => "application/json", "Authorization" => "Bearer test_key"]
                
                mock_response = Dict(
                    "data" => [
                        Dict("embedding" => rand(Float32, 1024)),
                        Dict("embedding" => rand(Float32, 1024))
                    ],
                    "usage" => Dict("total_tokens" => 100)
                )
                return HTTP.Response(200, JSON3.write(mock_response))
            end

            embedder = VoyageEmbedder(api_key="test_key", http_post=mock_http_post)
            docs = ["Voyage test document", "Another Voyage test"]
            
            embeddings = get_embeddings(embedder, docs)
            @test size(embeddings, 2) == length(docs)
            @test size(embeddings, 1) == 1024  # Assuming Voyage returns 1024-dimensional embeddings
        end
    end

    @testset "CombinedIndexBuilder" begin
        @testset "Constructor" begin
            builder = CombinedIndexBuilder(
                builders = [
                    create_jina_embedder(model="test-jina-model"),
                    create_voyage_embedder(model="test-voyage-model")
                ],
                top_k = 5
            )
            @test builder isa CombinedIndexBuilder
            @test length(builder.builders) == 2
            @test builder.builders[1] isa EmbedderSearch
            @test builder.builders[2] isa EmbedderSearch
        end

        @testset "get_index and call" begin
            # Mock HTTP post function for both Jina and Voyage
            function mock_http_post(url, headers, body)
                parsed_body = JSON3.read(body)
                if occursin("jina", url)
                    @test parsed_body["model"] == "test-jina-model"
                    mock_response = Dict(
                        "data" => [Dict("embedding" => rand(Float32, 512)) for _ in 1:length(parsed_body["input"])]
                    )
                elseif occursin("voyage", url)
                    @test parsed_body["model"] == "test-voyage-model"
                    mock_response = Dict(
                        "data" => [Dict("embedding" => rand(Float32, 1024)) for _ in 1:length(parsed_body["input"])],
                        "usage" => Dict("total_tokens" => 100)
                    )
                else
                    error("Unexpected URL: $url")
                end
                return HTTP.Response(200, JSON3.write(mock_response))
            end

            # Create mock embedders
            jina_embedder = create_jina_embedder(model="test-jina-model", top_k=5)
            voyage_embedder = create_voyage_embedder(model="test-voyage-model", top_k=5)

            # Override the http_post function in both embedders
            jina_embedder.embedder.embedder.http_post = mock_http_post
            voyage_embedder.embedder.embedder.http_post = mock_http_post

            builder = CombinedIndexBuilder(
                builders = [jina_embedder, voyage_embedder],
                top_k = 5
            )

            chunks = OrderedDict(
                "file1.jl" => "This is a test document for combined indexing.",
                "file2.jl" => "Another document to test the CombinedIndexBuilder.",
                "file3.jl" => "Third document for more comprehensive testing."
            )
            query = "test document"

            index = EasyContext.get_index(builder, chunks)
            @test index isa Vector{<:RAGTools.AbstractChunkIndex}
            @test length(index) == 2

            result = builder(index, query)
            @test result isa OrderedDict{String, String}
            @test length(result) <= 5  # Should return at most top_k results
            @test all(k -> k in keys(chunks), keys(result))
        end
    end

    @testset "Embedder Performance Comparisons" begin
    # Mock HTTP responses for consistent testing
    function mock_http_post(url, headers, body)
        dims = if occursin("jina", url)
            512
        elseif occursin("voyage", url)
            1024
        else # OpenAI
            1536
        end
        mock_response = Dict(
            "data" => [Dict("embedding" => rand(Float32, dims)) for _ in 1:length(JSON3.read(body)["input"])],
            "usage" => Dict("total_tokens" => 100)
        )
        return HTTP.Response(200, JSON3.write(mock_response))
    end

    # Test documents
    docs = ["Test document $(i) with some content for embedding comparison" for i in 1:20]
    query = "Find relevant code about embeddings"

    # Setup all embedder variants
    embedders = Dict(
        "OpenAI" => EmbeddingIndexBuilder(embedder=OpenAIBatchEmbedder(api_key="test", http_post=mock_http_post)),
        "Jina" => EmbeddingIndexBuilder(embedder=JinaEmbedder(api_key="test", http_post=mock_http_post)),
        "Voyage" => EmbeddingIndexBuilder(embedder=VoyageEmbedder(api_key="test", http_post=mock_http_post)),
        "Combined (OpenAI+BM25)" => create_combined_index_builder(EmbeddingIndexBuilder(embedder=OpenAIBatchEmbedder(api_key="test", http_post=mock_http_post))),
        "Combined (Jina+BM25)" => create_combined_index_builder(EmbeddingIndexBuilder(embedder=JinaEmbedder(api_key="test", http_post=mock_http_post))),
        "Combined (Voyage+BM25)" => create_combined_index_builder(EmbeddingIndexBuilder(embedder=VoyageEmbedder(api_key="test", http_post=mock_http_post)))
    )

    # Create test chunks
    chunks = OrderedDict(zip(["file$i.jl" for i in 1:20], docs))

    @testset "Embedding Dimensions" begin
        for (name, builder) in embedders
            index = get_index(builder, chunks)
            if builder isa CombinedIndexBuilder
                @test length(index) == 2  # Embedding + BM25
            else
                emb_size = if occursin("OpenAI", name)
                    1536
                elseif occursin("Jina", name)
                    512
                else # Voyage
                    1024
                end
                @test size(RAG.chunkdata(index), 1) == emb_size
            end
        end
    end

    @testset "Search Performance" begin
        # Warmup
        for builder in values(embedders)
            index = get_index(builder, chunks)
            builder(index, query)
        end

        results = Dict{String, BenchmarkTools.Trial}()
        
        for (name, builder) in embedders
            index = get_index(builder, chunks)
            results[name] = @benchmark $builder($index, $query)
        end

        # Print results in a sorted manner
        sorted_times = sort(collect(results), by=x->median(x.second))
        @info "Search Performance Rankings:"
        for (name, trial) in sorted_times
            @info "$name" median=median(trial) memory=trial.memory allocs=trial.allocs
        end

        # Basic performance assertions
        for (name, trial) in results
            if occursin("Combined", name)
                # Combined methods should take longer due to multiple searches
                @test median(trial) > median(results[replace(name, "Combined (" => "")[1:end-6]])
            end
        end
    end

    @testset "Result Quality" begin
        # Test if combined methods return more diverse results
        for (name, builder) in filter(p->occursin("Combined", p.first), embedders)
            index = get_index(builder, chunks)
            results = builder(index, query)
            
            # Get base embedder name
            base_name = replace(name, "Combined (" => "")[1:end-6]
            base_builder = embedders[base_name]
            base_index = get_index(base_builder, chunks)
            base_results = base_builder(base_index, query)
            
            # Combined should potentially find different/more results
            @test length(results) ≥ length(base_results)
        end
    end
end
