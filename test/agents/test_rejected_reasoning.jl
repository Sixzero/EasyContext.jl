using Test
using HTTP, Sockets, JSON3
using EasyContext
using EasyContext: Session, UserMessage, push_message!, create_AI_message, create_tool_message
using OpenRouter: swap_echo_port!

# A provider that rejects replayed reasoning state (signature bound to another prefix or
# account) must not end the turn: the state is dropped and the request resent once.
const OK_STREAM = """
event: message_start
data: {"type":"message_start","message":{"id":"x","type":"message","role":"assistant","content":[],"usage":{"input_tokens":1,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"done"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}

event: message_stop
data: {"type":"message_stop"}

"""
const SIG_REJECTED = """{"type":"error","error":{"type":"invalid_request_error","message":"messages.1.content.0: Invalid `signature` in `thinking` block"}}"""

"`rejects(body)` decides per request whether the fake provider answers 400; returns the request bodies, session and error."
function run_rejecting_turn(rejects)
    bodies = String[]
    server = HTTP.listen!("127.0.0.1", 0) do http
        body = String(read(http)); push!(bodies, body)
        if rejects(body)
            HTTP.setstatus(http, 400); HTTP.setheader(http, "Content-Type" => "application/json")
            HTTP.startwrite(http); write(http, SIG_REJECTED)
        else
            HTTP.setstatus(http, 200); HTTP.setheader(http, "Content-Type" => "text/event-stream")
            HTTP.setheader(http, "Content-Length" => string(sizeof(OK_STREAM)))
            HTTP.startwrite(http); write(http, OK_STREAM)
        end
    end
    port = Int(Sockets.getsockname(server.listener.server)[2])
    swap_echo_port!(8787, port)
    try
        agent = create_FluidAgent("echo_anthropic:test"; tools=Any[], extractor_type=NativeExtractor, sys_msg="sys")
        session = Session()
        push_message!(session, UserMessage(content="go"))
        push_message!(session, create_AI_message("thought about it"; reasoning="think", reasoning_model="test",
            reasoning_items=Any[Dict{String,Any}("type" => "thinking", "thinking" => "think", "signature" => "sig_stale")]))
        push_message!(session, UserMessage(content="and now?"))
        err = try work(agent, session; io=devnull, quiet=true); nothing catch e; e end
        return bodies, session, err
    finally
        swap_echo_port!(port, 8787)
        close(server)
    end
end

@testset "rejected reasoning replay is resent without the state" begin
    bodies, session, err = run_rejecting_turn(b -> occursin("sig_stale", b))
    @test err === nothing
    @test length(bodies) == 2
    @test occursin("sig_stale", bodies[1])                        # replayed to the model that produced it
    @test !occursin("sig_stale", bodies[2]) && occursin("thought about it", bodies[2])
    @test all(m -> m.reasoning_items === nothing, session.messages)
    @test session.messages[2].reasoning == "think"
    @test session.messages[end].content == "done"
end

@testset "a provider that keeps rejecting fails after one resend" begin
    bodies, _, err = run_rejecting_turn(_ -> true)
    @test err !== nothing
    @test length(bodies) == 2
end
