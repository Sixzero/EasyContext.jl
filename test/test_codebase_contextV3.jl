using Test
using EasyContext
using EasyContext: CodebaseContextV3, FullFileChunker, RAGContext, SourceChunk, AbstractFileSelector, get_project_files
using PromptingTools

# Define the RAG constant
const RAG = PromptingTools.Experimental.RAGTools

# Define a mock FullFileChunker
struct MockFullFileChunker <: RAG.AbstractChunker end

# Define a mock FileSelector
struct MockFileSelector <: AbstractFileSelector end

# Mock functions to simulate behavior of external dependencies
function mock_get_project_files(paths)
    return ["file1.jl", "file2.jl"]
end

function EasyContext.get_files_in_path(selector::MockFileSelector, path::String)
    return ["file1.jl", "file2.jl"]
end

function RAG.get_chunks(chunker::MockFullFileChunker, files::Vector{<:AbstractString}; kwargs...)
    return ["chunk1", "chunk2"], files
end

# Override the actual functions with our mocks
get_project_files(paths) = mock_get_project_files(paths)

@testset "CodebaseContextV3 Tests" begin
    @testset "Constructor" begin
        ctx = CodebaseContextV3(chunker=MockFullFileChunker(), file_selector=MockFileSelector())
        @test ctx.chunker isa MockFullFileChunker
        @test ctx.file_selector isa MockFileSelector
        @test isempty(ctx.project_paths)

        ctx = CodebaseContextV3(chunker=MockFullFileChunker(), file_selector=MockFileSelector(), project_paths=["path1", "path2"])
        @test ctx.chunker isa MockFullFileChunker
        @test ctx.file_selector isa MockFileSelector
        @test ctx.project_paths == ["path1", "path2"]
    end

    @testset "get_chunked_files" begin
        ctx = CodebaseContextV3(chunker=MockFullFileChunker(), file_selector=MockFileSelector(), project_paths=["path1"])
        chunks, sources = EasyContext.get_chunked_files(ctx)
        @test chunks == ["chunk1", "chunk2"]
        @test sources == ["file1.jl", "file2.jl"]
    end

    @testset "Functor call" begin
        ctx = CodebaseContextV3(chunker=MockFullFileChunker(), file_selector=MockFileSelector(), project_paths=["."])
        
        result = ctx("test question")
        @test result isa RAGContext
        @test result.chunk isa SourceChunk
        # @test length(result.chunk.sources) == 2  # We expect 2 sources
        # @test all(endswith.(result.chunk.sources, [".jl"]))  # All sources should end with .jl
        @test result.chunk.contexts == ["chunk1", "chunk2"]
        @test result.question == "test question"

        # Test with RAGContext input
        input_ragctx = RAGContext(SourceChunk(["src1"], ["chunk"]), "another question")
        result = ctx(input_ragctx)
        @test result.question == "another question"
    end

    @testset "get_context" begin
        ctx = CodebaseContextV3(chunker=MockFullFileChunker(), file_selector=MockFileSelector(), project_paths=["."])
        result = EasyContext.get_context(ctx, "test question")
        @test result isa RAGContext
        @test result.question == "test question"
    end

    @testset "cut_history!" begin
        ctx = CodebaseContextV3(chunker=MockFullFileChunker())
        # This should not throw an error
        @test_nowarn cut_history!(ctx, 5)
    end
end
;