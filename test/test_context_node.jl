using Test
using EasyContext: SourceChunk, ContextNode, add_or_update_source!, format_context_node, cut_history!, RAGContext

@testset "ContextNode" begin
    @testset "Constructor" begin
        node = ContextNode()
        @test node.title == "Docs"
        @test node.element == "Doc"
        @test isempty(node.attributes)
        @test isempty(node.tracked_sources)
        @test node.call_counter == 0
        @test isempty(node.updated_sources)
        @test isempty(node.new_sources)
    end
    @testset "add_or_update_source!" begin
        node = ContextNode()
        sources = ["./src/contexts/ContextNode.jl"]
        contexts = ["# Content of ContextNode.jl"]
        
        add_or_update_source!(node, sources, contexts)
        
        @test length(node.tracked_sources) == 1
        @test haskey(node.tracked_sources, sources[1])
        @test node.tracked_sources[sources[1]][2] == contexts[1]
        @test node.call_counter == 1
        @test length(node.new_sources) == 1
        @test isempty(node.updated_sources)

        # Update existing source
        new_context = ["# Updated content of ContextNode.jl"]
        add_or_update_source!(node, sources, new_context)
        
        @test length(node.tracked_sources) == 1
        @test node.tracked_sources[sources[1]][2] == new_context[1]
        @test node.call_counter == 2
        @test isempty(node.new_sources)
        @test length(node.updated_sources) == 1
    end

    @testset "Functor behavior" begin
        node = ContextNode()
        source = "./src/contexts/ContextNode.jl"
        context = "# Content of ContextNode.jl"
        result = RAGContext(SourceChunk([source], [context]), "test question")

        output = node(result)

        @test !isempty(output)
        @test occursin("<Docs NEW>", output)
        @test occursin("<File>", output)
        @test occursin(context, output)
        @test occursin("</File>", output)
        @test occursin("</Docs>", output)

        # Call again to test update behavior
        new_context = "# Updated content of ContextNode.jl"
        new_result = RAGContext(SourceChunk([source], [new_context]), "test question 2")

        output = node(new_result)

        @test !isempty(output)
        @test occursin("<Docs UPDATED>", output)
        @test occursin("<File>", output)
        @test occursin(new_context, output)
        @test occursin("</File>", output)
        @test occursin("</Docs>", output)
    end

    @testset "format_context_node" begin
        node = ContextNode()
        source = "./src/contexts/ContextNode.jl"
        context = "# Content of ContextNode.jl"
        
        add_or_update_source!(node, [source], [context])
        
        formatted = format_context_node(node)
        
        @test !isempty(formatted)
        @test occursin("<Docs NEW>", formatted)
        @test occursin("<File>", formatted)
        @test occursin(context, formatted)
        @test occursin("</File>", formatted)
        @test occursin("</Docs>", formatted)
        
        # Test that new_sources and updated_sources are emptied
        @test isempty(node.new_sources)
        @test isempty(node.updated_sources)
    end
end
