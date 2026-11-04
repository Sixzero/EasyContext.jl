using Test
using HTTP
using EasyContext
using EasyContext: Session, UserMessage, push_message!, MAX_TRUNCATIONS, TRUNCATION_NUDGE
using OpenRouter: swap_echo_port!

# A reply that hits max_tokens with only thinking (no text, no tool call) must not end
# the turn as if it were done: the loop records the cut-off, nudges and calls again.
sse(stop) = """
event: message_start
data: {"type":"message_start","message":{"id":"x","type":"message","role":"assistant","content":[],"usage":{"input_tokens":1,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"$(stop == "end_turn" ? "done" : "")"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"$stop"},"usage":{"output_tokens":1}}

event: message_stop
data: {"type":"message_stop"}

"""

function run_turn(stops)
    calls = Ref(0)
    port = 18797
    server = HTTP.serve!("127.0.0.1", port) do req
        calls[] += 1
        HTTP.Response(200, ["Content-Type" => "text/event-stream"]; body=sse(stops[min(calls[], end)]))
    end
    swap_echo_port!(8787, port)
    try
        agent = create_FluidAgent("echo_anthropic:test"; tools=Any[], extractor_type=NativeExtractor, sys_msg="sys")
        session = Session()
        push_message!(session, UserMessage(content="route it"))
        err = try
            work(agent, session; io=devnull, quiet=true); nothing
        catch e
            e
        end
        return calls[], session, err
    finally
        swap_echo_port!(port, 8787)
        close(server)
    end
end

@testset "max_tokens with nothing to run continues the turn" begin
    calls, session, err = run_turn(["max_tokens", "end_turn"])
    @test calls == 2
    @test err === nothing
    @test any(m -> m.role == :user && m.content == TRUNCATION_NUDGE, session.messages)
    @test session.messages[end].role == :assistant
    @test session.messages[end].content == "done"
end

@testset "repeated truncation is bounded and fails visibly" begin
    calls, session, err = run_turn(["max_tokens"])
    @test calls == MAX_TRUNCATIONS + 1
    @test err isa ErrorException && occursin("output-token limit", err.msg)
    @test session.messages[end].role == :assistant   # history stays valid for the next message
end

@testset "a normal end_turn ends after one call" begin
    calls, _, err = run_turn(["end_turn"])
    @test calls == 1
    @test err === nothing
end
