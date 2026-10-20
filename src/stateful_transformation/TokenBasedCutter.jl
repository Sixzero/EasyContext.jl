export TokenBasedCutter, estimate_conversation_tokens, token_usage_stats, record_real_usage!,
       current_context_tokens, get_effective_limit

"""
TokenBasedCutter: at `compact_threshold` of the context limit, summarize everything
before the last user turn and keep that turn verbatim. If the last turn alone exceeds
`target_ratio` of the limit (one long autonomous run), the cut lands inside it.
"""
@kwdef mutable struct TokenBasedCutter <: AbstractCutter
    context_limit::Int = 0          # 0 = auto from model, >0 = explicit limit
    model::String = ""              # Model name for auto context_limit lookup

    # `model => limit` the provider actually ENFORCED. Per-key/per-tier caps are
    # invisible to our model table and only a rejected request reveals them; without
    # remembering one, a session under such a cap would overflow (and destructively
    # recover) every few turns instead of compacting normally. Paired with its model
    # so a switch drops it.
    enforced_limit::Pair{String,Int} = "" => 0

    # Policy, not session state: hosts re-apply it from settings on every run.
    # false = no automatic compaction; manual `do_cut!` and `force_shrink!` still work.
    auto_compact::Bool = true

    compact_threshold::Float64 = 0.8    # Start compacting at 80% of limit
    target_ratio::Float64 = 0.1         # Max conversation kept after a cut, as a fraction of limit

    estimation_method::TokenEstimationMethod = CharCountDivTwo

    summarizer_model::String = SUMMARIZER_MODEL
    last_summary::String = ""
    # Removed source IDs since the host last reset tracking (synthetic summaries excluded).
    compacted_message_ids::Vector{String} = String[]
    # Monotonic count of cuts that actually rewrote history — bumped in
    # `summarize_and_cut!`, the single funnel every cut path goes through. Hosts
    # watch it to notice a rewrite without hooking each call site.
    cut_revision::Int = 0

    # Real-usage anchor: the provider's exact context size from the last API call,
    # paired with our char-estimate of the conversation at that same moment. From
    # there on only the DELTA since the anchor is estimated (see current_context_tokens).
    last_real_tokens::Int = 0
    last_real_estimate::Int = 0
end

# Quality/cost cap regardless of the model's advertised window (1M-context models
# degrade and get expensive well before their limit). Also keeps the compaction
# threshold (80% → 160K) aligned with the frontend indicator, which renders the
# ring against the same 200K standard cap.
const CONTEXT_CAP = 200_000

# chars/2 tracks real tokens only roughly (~0.5–1× for ASCII prose, tool JSON and
# code), so the delta since the anchor is scaled by this and never trusted on its own.
const EST_TO_REAL_RATIO = 0.5

# Slope for the delta since the anchor, capped so that removing the whole anchored
# conversation never extrapolates below 0 (`R − slope·E ≥ 0`).
delta_slope(cutter::TokenBasedCutter) =
    cutter.last_real_estimate > 0 ? min(EST_TO_REAL_RATIO, cutter.last_real_tokens / cutter.last_real_estimate) : EST_TO_REAL_RATIO

"""
    get_effective_limit(cutter::TokenBasedCutter) -> Int

Get the effective context limit: an explicit `context_limit` is respected as-is
(deliberate override); model lookup is capped at `CONTEXT_CAP`.
Returns 0 if not configured (disables token-based cutting).
"""
function get_effective_limit(cutter::TokenBasedCutter)
    configured = cutter.context_limit > 0 ? cutter.context_limit :
                 isempty(cutter.model) ? 0 : min(get_model_context_limit(cutter.model), CONTEXT_CAP)
    enforced_model, enforced = cutter.enforced_limit
    enforced > 0 && enforced_model == cutter.model || return configured
    return configured > 0 ? min(configured, enforced) : enforced
end

"""
    estimate_message_tokens(msg, method) -> Int

Estimate tokens in a single message (content + context). The per-message building
block for `estimate_conversation_tokens`, so both stay in sync.
"""
function estimate_message_tokens(msg, method::TokenEstimationMethod=CharCountDivTwo)
    total = estimate_tokens(msg.content, method)
    if hasproperty(msg, :context)
        for (_, v) in msg.context
            startswith(v, "data:") && continue  # skip base64 media (images, PDFs)
            total += estimate_tokens(v, method)
        end
    end
    return total
end

estimate_conversation_tokens(conv, method::TokenEstimationMethod=CharCountDivTwo) =
    sum(msg -> estimate_message_tokens(msg, method), conv.messages; init=0)

estimate_conversation_tokens(cutter::TokenBasedCutter, conv) =
    estimate_conversation_tokens(conv, cutter.estimation_method)

"""
    record_real_usage!(cutter::TokenBasedCutter, conv, real_tokens::Int)

Anchor the cutter to an exact context size reported by the provider API
(prompt + cache read/write). Call it when `conv` reflects EXACTLY the messages
that were sent in that API call, so the paired estimate snapshot is aligned.
"""
function record_real_usage!(cutter::TokenBasedCutter, conv, real_tokens::Int)
    real_tokens <= 0 && return
    cutter.last_real_tokens = real_tokens
    cutter.last_real_estimate = estimate_conversation_tokens(cutter, conv)
    nothing
end

"""
    current_context_tokens(cutter::TokenBasedCutter, conv) -> Int

`last_real_tokens + slope · (estimate_now − estimate_at_anchor)`: exact at the anchor
(so the fixed system prompt/tools overhead the char estimate cannot see is included),
only the conversation delta since the last call is estimated. Falls back to the raw
char estimate before any anchor.
"""
function current_context_tokens(cutter::TokenBasedCutter, conv)
    est = estimate_conversation_tokens(cutter, conv)
    cutter.last_real_tokens > 0 || return est
    round(Int, cutter.last_real_tokens + delta_slope(cutter) * (est - cutter.last_real_estimate))
end

function should_cut(cutter::TokenBasedCutter, conv)
    cutter.auto_compact || return false
    isempty(conv.messages) && return false
    limit = get_effective_limit(cutter)
    limit <= 0 && return false

    # No real-usage anchor yet (fresh flow, or one deserialized from a pre-anchor
    # blob): the raw chars/2 estimate overruns real tokens ~1.5-2x for ASCII and would
    # fire compaction way too early. The first LLM call always records an anchor.
    cutter.last_real_tokens > 0 || return false

    current_context_tokens(cutter, conv) < limit * cutter.compact_threshold && return false

    # Only compact if a cut would actually drop a real message. Right after a
    # compaction the kept window (or a single oversized message) can still exceed
    # the threshold; re-cutting then frees nothing and just re-summarizes the same
    # prefix forever. would_free_messages is the principled stop for that churn.
    return would_free_messages(conv, calculate_keep(cutter, conv))
end

"""
    calculate_keep(cutter::TokenBasedCutter, conv) -> Int

Keep the last user turn (from the last real `:user` message on), so a turn is never
split between the summary and the kept window. If that turn alone exceeds the
post-cut budget (`target_ratio · limit`, in estimate units), keep only as many of
its newest messages as fit — `history_cut_start` then aligns the boundary off
`:tool` results so a tool_use/tool_result pair stays intact. With no user message
left (a turn already cut mid-way) the budget walk alone decides.
"""
function calculate_keep(cutter::TokenBasedCutter, conv)
    n = length(conv.messages)
    turn_start = something(findlast(m -> m.role == :user && !is_prior_context(m), conv.messages), 1)
    limit = get_effective_limit(cutter)
    budget = limit > 0 ? limit * cutter.target_ratio / EST_TO_REAL_RATIO : Inf
    first_kept = n + 1
    acc = 0
    while first_kept > turn_start
        acc += estimate_message_tokens(conv.messages[first_kept-1], cutter.estimation_method)
        acc > budget && first_kept <= n && break
        first_kept -= 1
    end
    return n - first_kept + 1
end

function record_compacted_messages!(cutter::TokenBasedCutter, messages)
    append!(cutter.compacted_message_ids, (m.id for m in messages if !is_prior_context(m)))
end

function do_cut!(cutter::TokenBasedCutter, conv; keep::Union{Int,Nothing}=nothing)
    # Validate explicit input even for an empty conversation (auto may keep zero).
    isnothing(keep) || history_cut_start(conv.messages, keep)
    keep = something(keep, calculate_keep(cutter, conv))
    length(conv.messages) <= keep && return cutter.last_summary

    tokens_before = estimate_conversation_tokens(cutter, conv)
    summarize_and_cut!(cutter, conv; keep)
    # No re-anchoring: current_context_tokens scales the estimate DELTA since the
    # anchor, so the removed tokens drop out of the reported size by themselves.
    @info "TokenBasedCutter: cut conversation" kept=length(conv.messages) tokens_freed=tokens_before-estimate_conversation_tokens(cutter, conv) post_tokens=current_context_tokens(cutter, conv)
    return cutter.last_summary
end

function get_cache_setting(cutter::TokenBasedCutter, conv)
    isempty(conv.messages) && return :all
    limit = get_effective_limit(cutter)
    limit <= 0 && return :all

    # Only skip caching the last block if a compaction is actually imminent — i.e. it
    # would free a real message. Otherwise we'd disable caching forever whenever the
    # kept window alone sits near the threshold (nothing left to compact).
    if current_context_tokens(cutter, conv) >= limit * (cutter.compact_threshold - 0.05) &&
       would_free_messages(conv, calculate_keep(cutter, conv))
        return :all_but_last
    end
    return :all
end

"""
    release_older_media!(conv; prefix="data:", need=nothing) -> Bool

Keep the newest message carrying matching media; drop older matching payloads (oldest
first), leaving their text/path so the agent can reread them. `prefix="data:image/"`
limits it to images. `need` stops once that many payloads are gone, and if the older
messages cannot supply that many, nothing is touched. True if anything was released.
"""
function release_older_media!(conv; prefix::AbstractString="data:", need::Union{Int,Nothing}=nothing)
    is_media(v) = startswith(v, prefix)
    latest_media = findlast(msg -> any(is_media, values(msg.context)), conv.messages)
    latest_media === nothing && return false
    older = @view conv.messages[1:latest_media-1]
    need === nothing || sum(msg -> count(is_media, values(msg.context)), older; init=0) >= need || return false
    released = 0
    for msg in older
        need !== nothing && released >= need && break
        keys_to_drop = [k for (k, v) in msg.context if is_media(v)]
        isempty(keys_to_drop) && continue
        foreach(k -> delete!(msg.context, k), keys_to_drop)
        msg.content *= "\n[Earlier media released to fit the request limits; reread the source if needed.]"
        released += length(keys_to_drop)
    end
    released > 0
end

"""
    force_shrink!(cutter::TokenBasedCutter, conv, real_tokens::Int, limit::Int) -> Bool

Emergency shrink after the provider rejected the request as too long. Deliberately
NOT `maybe_cut!`: that path is gated on `should_cut`, which stays false forever
here, since it needs an anchor and anchors come only from SUCCESSFUL calls.
`real_tokens`/`limit` come from the error — the one place they exist on a failure.

Two stages for two different failures: summarize+cut history, then truncate a single
oversized message — the case cutting CANNOT fix, since a message larger than the
window survives every cut and would loop forever.
"""
function force_shrink!(cutter::TokenBasedCutter, conv, real_tokens::Int, limit::Int)
    limit > 0 || return false
    tokens_before = estimate_conversation_tokens(cutter, conv)

    # A rejected call is still a valid real-usage anchor, and remembering the limit
    # it enforced lets later turns compact before overflowing again.
    real_tokens > 0 && record_real_usage!(cutter, conv, real_tokens)
    cutter.enforced_limit = cutter.model => limit

    keep = calculate_keep(cutter, conv)
    would_free_messages(conv, keep) && summarize_and_cut!(cutter, conv; keep)

    # Cutting cannot remove a message that is oversized ON ITS OWN, so truncate those
    # in place to the post-cut token target, converted to chars (estimate = chars/2).
    msg_cap_chars = round(Int, limit * cutter.target_ratio / delta_slope(cutter))
    marker(dropped) = "\n\n…[$dropped characters dropped — this message alone did not fit the model's context window]…\n\n"
    for msg in conv.messages
        chars = length(msg.content)
        chars <= msg_cap_chars && continue
        # The marker counts against the cap: leaving the result marginally over it
        # would let each later call shave off a few more chars, reporting "progress"
        # forever. Too small a cap to hold both means truncating cannot help here.
        tail = msg_cap_chars ÷ 5
        head = msg_cap_chars - tail - length(marker(chars))
        head > 0 || continue
        msg.content = string(first(msg.content, head), marker(chars - head - tail), last(msg.content, tail))
    end

    # Media is invisible to the char estimate. Repeated image/PDF reads can alone
    # overflow even after text compaction.
    media_removed = release_older_media!(conv)

    tokens_after = estimate_conversation_tokens(cutter, conv)
    @warn "force_shrink!: context overflow recovery" real_tokens limit tokens=tokens_before=>tokens_after
    tokens_after < tokens_before || media_removed
end

"""
    token_usage_stats(cutter::TokenBasedCutter, conv) -> NamedTuple

Get current token usage statistics for debugging/monitoring.
"""
function token_usage_stats(cutter::TokenBasedCutter, conv)
    context_limit = get_effective_limit(cutter)
    current_tokens = current_context_tokens(cutter, conv)
    (
        current_tokens = current_tokens,
        context_limit = context_limit,
        threshold_tokens = round(Int, context_limit * cutter.compact_threshold),
        target_tokens = round(Int, context_limit * cutter.target_ratio),
        percentage_used = context_limit > 0 ? round(100 * current_tokens / context_limit; digits=1) : 0.0,
        messages_count = length(conv.messages),
        will_cut = should_cut(cutter, conv),
        would_keep = calculate_keep(cutter, conv),
    )
end
