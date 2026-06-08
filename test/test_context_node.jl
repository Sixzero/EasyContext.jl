using Test
using Dates: now, UTC
using EasyContext: SourceChunk, ContextNode, add_or_update_source!, format_context_node, cut_history!, history_cut_start, RAGContext, Session, Message

@testset "cut_history! tool boundary" begin
    mkmsgs() = begin
        c = Session()
        add!(role, content) = push!(c.messages, Message(timestamp=now(UTC), role=role, content=content))
        add!(:user, "u1"); add!(:assistant, "a1"); add!(:tool, "t1"); add!(:assistant, "a2")
        add!(:user, "u2"); add!(:assistant, "a3"); add!(:tool, "t2"); add!(:assistant, "a4")
        c.messages
    end
    msgs = mkmsgs()
    for k in 2:8
        cut_start = history_cut_start(msgs, k)
        # Window must start on a real :user turn (never an orphaned :tool/:assistant).
        @test msgs[cut_start].role == :user
        # The removed prefix and the kept window partition the messages exactly —
        # no overlap (duplicate summary) and no gap (silent loss).
        @test cut_start >= 1 && cut_start <= length(msgs)
        kept_n = length(msgs) - cut_start + 1
        @test kept_n >= k
        # cut_history! mutates to the same boundary history_cut_start reports.
        c = Session(); append!(c.messages, deepcopy(msgs))
        cut_history!(c; keep=k)
        @test length(c.messages) == kept_n
        @test c.messages[1].role == :user
    end
end

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
