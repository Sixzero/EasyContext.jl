using Test
using HTTP, Sockets
using EasyContext
using EasyContext: Session, UserMessage, push_message!, MAX_MIDSTREAM_RESUMES, MIDSTREAM_NUDGE, StreamDroppedError
using OpenRouter: swap_echo_port!

# A stream that dies after some text (no message_stop) must not end the turn with a raw
# EOF error: the partial reply is kept, the model is nudged on, and it is bounded.
const HEAD = """
event: message_start
data: {"type":"message_start","message":{"id":"x","type":"message","role":"assistant","content":[],"usage":{"input_tokens":1,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

"""
delta(t) = """
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"$t"}}

"""
const TAIL = """
event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}

event: message_stop
data: {"type":"message_stop"}

"""

function run_midstream_turn(script; midstream=:continue, kw...)   # script[i]: :drop (partial, hard close), :reset (closed before any chunk) or :ok
    calls = Ref(0)
    server = HTTP.listen!("127.0.0.1", 0) do http
        calls[] += 1
        read(http)   # consume the request body before answering
        step = script[min(calls[], end)]
        step == :reset && (close(http.stream); return)
        drop = step == :drop
        body = drop ? HEAD * delta("half") : HEAD * delta("done") * TAIL
        HTTP.setstatus(http, 200)
        HTTP.setheader(http, "Content-Type" => "text/event-stream")
        drop || HTTP.setheader(http, "Content-Length" => string(sizeof(body)))
        HTTP.startwrite(http)
        write(http, body)
        drop && (flush(http.stream); close(http.stream))   # socket dies mid-reply, no done marker
    end
    port = Int(Sockets.getsockname(server.listener.server)[2])
    retries = String[]
    swap_echo_port!(8787, port)
    try
        agent = create_FluidAgent("echo_anthropic:test"; tools=Any[], extractor_type=NativeExtractor, sys_msg="sys")
        session = Session()
        push_message!(session, UserMessage(content="go"))
        resp = nothing
        err = try
            resp = work(agent, session; io=devnull, quiet=true, midstream, kw..., on_retry=(a, n, w, m) -> push!(retries, m)); nothing
        catch e
            e
        end
        return calls[], session, err, retries, resp
    finally
        swap_echo_port!(port, 8787)
        close(server)
    end
end

@testset "mid-stream drop resumes with the partial reply kept" begin
    calls, session, err, retries, _ = run_midstream_turn([:drop, :ok])
    @test err === nothing
    @test calls == 2
    @test any(m -> m.role == :assistant && startswith(m.content, "half") && occursin("connection dropped", m.content), session.messages)
    @test any(m -> m.role == :user && m.content == MIDSTREAM_NUDGE, session.messages)
    @test session.messages[end].content == "done"
    @test length(retries) == 1 && occursin("dropped mid-reply", retries[1])
end

@testset "repeated mid-stream drops are bounded" begin
    calls, session, err, _, _ = run_midstream_turn([:drop])
    @test err isa StreamDroppedError
    @test calls == MAX_MIDSTREAM_RESUMES + 1
    # The last attempt's text is kept too, so a manual Continue resumes from what was shown.
    @test count(m -> m.role == :assistant && occursin("connection dropped", m.content), session.messages) == MAX_MIDSTREAM_RESUMES + 1
    @test session.messages[end].role == :assistant
end

@testset ":resend (single-result callers) restarts the reply, never hands back a tail" begin
    calls, session, err, _, resp = run_midstream_turn([:drop, :ok]; midstream=:resend)
    @test err === nothing && calls == 2
    @test resp.content == "done"
    @test !any(m -> occursin("connection dropped", m.content) || m.content == MIDSTREAM_NUDGE, session.messages)
end

@testset "a retry that dies before its first chunk still reports a dropped stream" begin
    calls, session, err, _, _ = run_midstream_turn([:drop, :reset])
    @test err isa StreamDroppedError
    @test session.messages[end].role == :assistant || session.messages[end].content == MIDSTREAM_NUDGE
end

@testset "a retry doesn't use up the iteration budget (MAX_ITERATIONS=1 callers)" begin
    calls, _, err, _, resp = run_midstream_turn([:drop, :ok]; midstream=:resend, MAX_ITERATIONS=1)
    @test err === nothing && calls == 2
    @test resp.content == "done"
end
