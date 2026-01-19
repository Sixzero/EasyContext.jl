export ContextCompactor, should_compact, do_compact!, context_usage_stats,
       estimate_context_tokens, get_model_context_limit, get_effective_context_limit,
       set_models_data_path!, load_model_context_limits

using JSON3

"""
ContextCompactor handles conversation compacting based on context/token size.
Uses Option B: Hybrid approach with minimum messages + token budget.

When compacting triggers (at compact_threshold of context_limit):
1. Keep at least `min_keep_messages` recent messages
2. Try to cut down to `target_after_compact` of context_limit
3. If min messages exceed target, keep min messages anyway (safety)
"""
@kwdef mutable struct ContextCompactor
    # Context limit configuration
    context_limit::Int = 0  # 0 = auto from model, >0 = explicit limit
    model::String = ""      # Model name for auto context_limit lookup

    # Compacting thresholds
    compact_threshold::Float64 = 0.8    # Trigger compacting at 80% of limit
    target_after_compact::Float64 = 0.3 # Target 30% of limit after compacting
    min_keep_messages::Int = 4          # Always keep at least 4 messages

    # Token estimation
    estimation_method::TokenEstimationMethod = CharCountDivTwo

    # Summarization
    summarizer_model::String = "claudeh"
    last_summary::String = ""
end

# ============================================================================
# Model context limits from models_data.json
# ============================================================================

const _MODEL_CONTEXT_CACHE = Ref{Union{Nothing, Dict{String, Int}}}(nothing)
const _MODELS_DATA_PATH = Ref{String}("")

"""
    set_models_data_path!(path::String)

Set the path to models_data.json. Call this before using get_model_context_limit.
"""
function set_models_data_path!(path::String)
    _MODELS_DATA_PATH[] = path
    _MODEL_CONTEXT_CACHE[] = nothing  # Clear cache to reload
end

"""
    get_models_data_path() -> String

Get the path to models_data.json. Checks in order:
1. Explicitly set path via set_models_data_path!
2. MODELS_DATA_PATH environment variable
3. Default path in EasyContext.jl/data
"""
function get_models_data_path()
    !isempty(_MODELS_DATA_PATH[]) && return _MODELS_DATA_PATH[]

    env_path = get(ENV, "MODELS_DATA_PATH", "")
    !isempty(env_path) && return env_path

    default_path = joinpath(@__DIR__, "..", "..", "data", "models_data.json")
    isfile(default_path) && return default_path

    return ""
end

"""
    load_model_context_limits() -> Dict{String, Int}

Load and parse models_data.json, building a model_id -> context_length mapping.
Takes the maximum context_length across all endpoints for each model.
"""
function load_model_context_limits()
    !isnothing(_MODEL_CONTEXT_CACHE[]) && return _MODEL_CONTEXT_CACHE[]

    path = get_models_data_path()
    if isempty(path) || !isfile(path)
        @warn "models_data.json not found, using empty model limits" path
        _MODEL_CONTEXT_CACHE[] = Dict{String, Int}()
        return _MODEL_CONTEXT_CACHE[]
    end

    try
        data = JSON3.read(read(path, String))
        limits = Dict{String, Int}()

        for model in get(data, :models, [])
            model_id = get(model, :id, "")
            isempty(model_id) && continue

            max_context = 0
            for endpoint in get(model, :endpoints, [])
                ctx_len = get(endpoint, :context_length, 0)
                max_context = max(max_context, ctx_len)
            end

            max_context > 0 && (limits[model_id] = max_context)
        end

        @info "Loaded model context limits" path num_models=length(limits)
        _MODEL_CONTEXT_CACHE[] = limits
        return limits
    catch e
        @error "Failed to load models_data.json" path exception=e
        _MODEL_CONTEXT_CACHE[] = Dict{String, Int}()
        return _MODEL_CONTEXT_CACHE[]
    end
end

"""
    get_model_context_limit(model::String) -> Int

Get the context limit for a model from models_data.json.
Returns 200000 (Claude default) if model not found.
"""
function get_model_context_limit(model::String)
    isempty(model) && return 200000

    limits = load_model_context_limits()

    haskey(limits, model) && return limits[model]

    # Prefix match
    model_lower = lowercase(model)
    for (key, limit) in limits
        if startswith(lowercase(key), model_lower) || startswith(model_lower, lowercase(key))
            return limit
        end
    end

    return 200000
end

# ============================================================================
# Token estimation
# ============================================================================

"""
    estimate_context_tokens(conv::Session, method::TokenEstimationMethod=CharCountDivTwo) -> Int

Estimate the total tokens used by a conversation's messages.
"""
function estimate_context_tokens(conv::Session, method::TokenEstimationMethod=CharCountDivTwo)
    total = 0
    for msg in conv.messages
        total += estimate_tokens(msg.content, method)
        for (_, v) in msg.context
            startswith(v, "data:image") && continue
            total += estimate_tokens(v, method)
        end
    end
    return total
end

estimate_context_tokens(compactor::ContextCompactor, conv::Session) =
    estimate_context_tokens(conv, compactor.estimation_method)

"""
    estimate_message_tokens(msg::Message, method::TokenEstimationMethod) -> Int

Estimate tokens for a single message.
"""
function estimate_message_tokens(msg, method::TokenEstimationMethod=CharCountDivTwo)
    total = estimate_tokens(msg.content, method)
    for (_, v) in msg.context
        startswith(v, "data:image") && continue
        total += estimate_tokens(v, method)
    end
    return total
end

# ============================================================================
# Context limit helpers
# ============================================================================

"""
    get_effective_context_limit(compactor::ContextCompactor) -> Int

Get the effective context limit from explicit config or model lookup.
Returns 0 if not configured (disables context-based compacting).
"""
function get_effective_context_limit(compactor::ContextCompactor)
    compactor.context_limit > 0 && return compactor.context_limit
    isempty(compactor.model) && return 0
    return get_model_context_limit(compactor.model)
end

# ============================================================================
# Compacting logic
# ============================================================================

"""
    should_compact(compactor::ContextCompactor, conv::Session) -> Bool

Check if compacting should be triggered based on context size threshold.
"""
function should_compact(compactor::ContextCompactor, conv::Session)
    limit = get_effective_context_limit(compactor)
    limit <= 0 && return false

    current_tokens = estimate_context_tokens(compactor, conv)
    threshold = limit * compactor.compact_threshold
    return current_tokens >= threshold
end

"""
    calculate_keep_count(compactor::ContextCompactor, conv::Session) -> Int

Calculate how many messages to keep using Option B hybrid logic:
1. Start with min_keep_messages
2. If that's under target_after_compact tokens, try to keep more
3. Never keep fewer than min_keep_messages
"""
function calculate_keep_count(compactor::ContextCompactor, conv::Session)
    limit = get_effective_context_limit(compactor)
    target_tokens = limit > 0 ? round(Int, limit * compactor.target_after_compact) : 60000

    messages = conv.messages
    n = length(messages)
    n <= compactor.min_keep_messages && return n

    # Calculate tokens from the end, find how many fit in target
    total_tokens = 0
    keep_count = 0

    for i in n:-1:1
        msg_tokens = estimate_message_tokens(messages[i], compactor.estimation_method)
        if total_tokens + msg_tokens <= target_tokens || keep_count < compactor.min_keep_messages
            total_tokens += msg_tokens
            keep_count += 1
        else
            break
        end
    end

    # Ensure we keep at least min_keep_messages
    return max(keep_count, compactor.min_keep_messages)
end

"""
    do_compact!(compactor::ContextCompactor, conv::Session; keep::Union{Int,Nothing}=nothing) -> String

Compact the conversation: summarize old messages, cut, prepend summary.
Returns the generated summary.

If `keep` is not provided, uses calculate_keep_count for adaptive cutting.
"""
function do_compact!(compactor::ContextCompactor, conv::Session; keep::Union{Int,Nothing}=nothing)
    keep = something(keep, calculate_keep_count(compactor, conv))

    length(conv.messages) <= keep && return compactor.last_summary

    # Ensure we don't start with an assistant message after cutting
    if keep > 0 && keep <= length(conv.messages)
        cut_start = length(conv.messages) - keep + 1
        if conv.messages[cut_start].role === :assistant && keep > 1
            keep -= 1
        end
    end

    # Summarize messages to be cut
    messages_to_cut = conv.messages[1:end-keep]
    compactor.last_summary = summarize_conversation(
        messages_to_cut;
        model=compactor.summarizer_model,
        previous_summary=compactor.last_summary
    )

    # Cut
    conv.messages = conv.messages[end-keep+1:end]

    # Prepend summary to first kept user message
    if !isempty(compactor.last_summary) && !isempty(conv.messages) && conv.messages[1].role == :user
        conv.messages[1].content = "<prior_context>\n$(compactor.last_summary)\n</prior_context>\n\n" * conv.messages[1].content
    end

    @info "Conversation compacted" kept=length(conv.messages) summary_length=length(compactor.last_summary)
    return compactor.last_summary
end

"""
    maybe_compact!(compactor::ContextCompactor, conv::Session) -> Bool

Check if compacting is needed and do it if so. Returns true if compacted.
"""
function maybe_compact!(compactor::ContextCompactor, conv::Session)
    if should_compact(compactor, conv)
        limit = get_effective_context_limit(compactor)
        current_tokens = estimate_context_tokens(compactor, conv)
        @info "Compacting triggered by context size" current_tokens threshold=limit*compactor.compact_threshold context_limit=limit
        do_compact!(compactor, conv)
        return true
    end
    return false
end

# ============================================================================
# Monitoring / debugging
# ============================================================================

"""
    context_usage_stats(compactor::ContextCompactor, conv::Session) -> NamedTuple

Get current context usage statistics.
"""
function context_usage_stats(compactor::ContextCompactor, conv::Session)
    context_limit = get_effective_context_limit(compactor)
    current_tokens = estimate_context_tokens(compactor, conv)
    threshold_tokens = context_limit > 0 ? context_limit * compactor.compact_threshold : 0
    target_tokens = context_limit > 0 ? context_limit * compactor.target_after_compact : 0

    (
        current_tokens = current_tokens,
        context_limit = context_limit,
        threshold_tokens = round(Int, threshold_tokens),
        target_tokens = round(Int, target_tokens),
        percentage_used = context_limit > 0 ? round(100 * current_tokens / context_limit; digits=1) : 0.0,
        messages_count = length(conv.messages),
        will_compact = context_limit > 0 && current_tokens >= threshold_tokens,
        would_keep = calculate_keep_count(compactor, conv),
    )
end

"""
    get_cache_setting(compactor::ContextCompactor, conv::Session) -> Symbol

Get cache setting based on proximity to compacting threshold.
Returns :all_but_last if near threshold (within 5%), :all otherwise.
"""
function get_cache_setting(compactor::ContextCompactor, conv::Session)
    context_limit = get_effective_context_limit(compactor)
    context_limit <= 0 && return :all

    current_tokens = estimate_context_tokens(compactor, conv)
    near_threshold = context_limit * (compactor.compact_threshold - 0.05)

    if current_tokens >= near_threshold
        @info "Not caching - near compacting threshold" current_tokens near_threshold
        return :all_but_last
    end
    return :all
end
