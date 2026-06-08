using Test
using OpenRouter: AIMessage, UserMessage, ToolMessage
using EasyContext: Session, push_message!, ensure_tool_results!, to_PT_messages
import PromptingTools as PT

@testset "tool pairing" begin
    tc(id) = [Dict{String,Any}("id" => id, "name" => "f", "args" => Dict{String,Any}())]

    @testset "AIMessage merge guard preserves tool_calls" begin
        # Plain consecutive assistant turns merge.
        s = Session()
        push_message!(s, AIMessage(content="a1"))
        push_message!(s, AIMessage(content="a2"))
        @test length(s.messages) == 1
        @test s.messages[end].content == "a1\na2"

        # An incoming assistant with tool_calls must NOT merge into the previous
        # plain assistant — otherwise the tool_use would be dropped.
        push_message!(s, AIMessage(content="calls", tool_calls=tc("c1")))
        @test length(s.messages) == 2
        @test s.messages[end].tool_calls !== nothing

        # A plain assistant must NOT merge into a previous assistant carrying tool_calls.
        push_message!(s, AIMessage(content="after"))
        @test length(s.messages) == 3
        @test s.messages[end].tool_calls === nothing
    end

    @testset "UserMessage never merges into a :tool message" begin
        s = Session()
        push_message!(s, AIMessage(content="calls", tool_calls=tc("c1")))
        push_message!(s, ToolMessage(content="result", tool_call_id="c1"))
        push_message!(s, UserMessage(content="hi"))
        # The user message must be its own message, not appended to the tool_result.
        @test s.messages[end].role == :user
        @test s.messages[end].content == "hi"
        @test s.messages[end-1].role == :tool
        @test s.messages[end-1].content == "result"
    end

    @testset "consecutive user messages still merge" begin
        s = Session()
        push_message!(s, UserMessage(content="u1"))
        push_message!(s, UserMessage(content="u2"))
        @test length(s.messages) == 1
        @test s.messages[end].content == "u1\nu2"
    end

    @testset "no orphaned tool_result reaches the API" begin
        # An assistant tool_use whose result was lost, plus an orphan tool_result.
        s = Session()
        push_message!(s, UserMessage(content="u"))
        push_message!(s, AIMessage(content="calls", tool_calls=tc("c1")))
        push_message!(s, ToolMessage(content="orphan", tool_call_id="zzz"))  # no matching tool_use
        pt = to_PT_messages(s, "sys")
        # Orphan tool_result dropped; missing result for c1 gets a placeholder.
        ids_with_tooluse = Set{String}()
        for m in pt
            m isa PT.AIMessage && m.tool_calls !== nothing && foreach(tcd -> push!(ids_with_tooluse, tcd["id"]), m.tool_calls)
        end
        for m in pt
            m isa PT.ToolMessage && @test m.tool_call_id in ids_with_tooluse
        end
    end
end
