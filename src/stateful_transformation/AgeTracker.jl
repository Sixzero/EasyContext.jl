export AgeTracker, cut_old_sources!, cut_old_conversation_history!, force_compact!,
       estimate_context_tokens, get_model_context_limit, get_effective_context_limit,
       context_usage_stats, set_models_data_path!, load_model_context_limits

@kwdef mutable struct AgeTracker
    tracker::Dict{String, Int} = Dict{String, Int}()
    # Legacy message-count based compacting (disabled when context_limit is set)
    max_history::Int = 14
    cut_to::Int = 6
    age::Int = 0
    last_message_count::Int = 0
    # Context-size based compacting
    context_limit::Int = 0  # 0 = use message count, >0 = use context size (in tokens)
    compact_threshold::Float64 = 0.8  # Trigger at 80% of context_limit
    model::String = ""  # Optional: model name for auto context_limit lookup
    estimation_method::TokenEstimationMethod = CharCountDivTwo
    # Summarization
    summarizer_model::String = "claudeh"
    last_summary::String = ""
end

using JSON3

# Cached model context limits loaded from models_data.json
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
3. Default relative path from workspace
"""
function get_models_data_path()
    # 1. Explicitly set path
    !isempty(_MODELS_DATA_PATH[]) && return _MODELS_DATA_PATH[]

    # 2. Environment variable
    env_path = get(ENV, "MODELS_DATA_PATH", "")
    !isempty(env_path) && return env_path

    # 3. Default path - EasyContext.jl/data is the canonical location
    default_paths = [
        joinpath(@__DIR__, "..", "..", "data", "models_data.json"),
    ]
    for p in default_paths
        isfile(p) && return p
    end

    return ""
end

"""
    load_model_context_limits() -> Dict{String, Int}

Load and parse models_data.json, building a model_id -> context_length mapping.
Takes the maximum context_length across all endpoints for each model.
"""
function load_model_context_limits()
    # Return cached if available
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

            # Get max context_length across all endpoints
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
Supports exact match and prefix matching (e.g., "anthropic/claude" matches "anthropic/claude-3-sonnet").
"""
function get_model_context_limit(model::String)
    isempty(model) && return 200000

    limits = load_model_context_limits()

    # Exact match first
    haskey(limits, model) && return limits[model]

    # Prefix match (useful for model variants)
    model_lower = lowercase(model)
    for (key, limit) in limits
        if startswith(lowercase(key), model_lower) || startswith(model_lower, lowercase(key))
            return limit
        end
    end

    # Default to Claude's context size
    return 200000
end

"""
    estimate_context_tokens(conv::Session, method::TokenEstimationMethod=CharCountDivTwo) -> Int

Estimate the total tokens used by a conversation's messages (including their context dicts).
"""
function estimate_context_tokens(conv::Session, method::TokenEstimationMethod=CharCountDivTwo)
    total = 0
    for msg in conv.messages
        # Message content
        total += estimate_tokens(msg.content, method)
        # Context dict values (embedded files, images as text, etc.)
        for (_, v) in msg.context
            # Skip base64 images - they have special token counting
            startswith(v, "data:image") && continue
            total += estimate_tokens(v, method)
        end
    end
    return total
end

"""
    estimate_context_tokens(tracker::AgeTracker, conv::Session) -> Int

Estimate context tokens using the tracker's configured estimation method.
"""
estimate_context_tokens(tracker::AgeTracker, conv::Session) =
    estimate_context_tokens(conv, tracker.estimation_method)

"""
    get_effective_context_limit(tracker::AgeTracker) -> Int

Get the effective context limit, either from tracker config or model lookup.
"""
function get_effective_context_limit(tracker::AgeTracker)
    tracker.context_limit > 0 && return tracker.context_limit
    isempty(tracker.model) && return 0  # No limit configured, use message count
    return get_model_context_limit(tracker.model)
end

"""
    should_compact_by_context(tracker::AgeTracker, conv::Session) -> Bool

Check if compacting should be triggered based on context size threshold.
Returns false if context-based compacting is not configured.
"""
function should_compact_by_context(tracker::AgeTracker, conv::Session)
    limit = get_effective_context_limit(tracker)
    limit <= 0 && return false  # Not configured, fall back to message count

    current_tokens = estimate_context_tokens(tracker, conv)
    threshold = limit * tracker.compact_threshold
    return current_tokens >= threshold
end

function register_changes!(ager::AgeTracker, tracker::ChangeTracker)
    for (source, state) in tracker.changes
        if state === :UPDATED || state === :NEW
            ager.tracker[source] = ager.age
        end
    end
end

function cut_old_sources!(sources_to_delete::Vector{String}, ctx::Context, ct::ChangeTracker) 
    cut_old_sources!(sources_to_delete, ctx.d, ct)
end

function cut_old_sources!(sources_to_delete::Vector{String}, ctx::OrderedDict, ct::ChangeTracker)
    for source in sources_to_delete
        delete!(ctx, source)
        delete!(ct.changes, source)
        delete!(ct.chunks_dict, source)
    end
    return sources_to_delete
end

"""
    do_compact!(age_tracker::AgeTracker, conv::Session, keep::Int) -> String

Core compaction logic: summarize messages being cut, then cut, then prepend summary.
Returns the generated summary.
"""
function do_compact!(age_tracker::AgeTracker, conv::Session, keep::Int)
    length(conv.messages) <= keep && return age_tracker.last_summary

    # Summarize messages to be cut
    messages_to_cut = conv.messages[1:end-keep]
    age_tracker.last_summary = summarize_conversation(
        messages_to_cut;
        model=age_tracker.summarizer_model,
        previous_summary=age_tracker.last_summary
    )

    # Cut
    conv.messages = conv.messages[end-keep+1:end]

    # Prepend summary to first kept user message
    if !isempty(age_tracker.last_summary) && !isempty(conv.messages) && conv.messages[1].role == :user
        conv.messages[1].content = "<prior_context>\n$(age_tracker.last_summary)\n</prior_context>\n\n" * conv.messages[1].content
    end

    age_tracker.last_message_count = length(conv.messages)
    return age_tracker.last_summary
end

function cut_old_conversation_history!(age_tracker::AgeTracker, conv::Session, contexts...)
    current_msg_count = length(conv.messages)
    age_tracker.age += current_msg_count - age_tracker.last_message_count

    # Determine if compacting should be triggered
    # Priority: context-based (if configured) > message-count based
    context_limit = get_effective_context_limit(age_tracker)
    should_compact = if context_limit > 0
        # Context-size based compacting
        current_tokens = estimate_context_tokens(age_tracker, conv)
        threshold = context_limit * age_tracker.compact_threshold
        if current_tokens >= threshold
            @info "Compacting triggered by context size" current_tokens threshold context_limit
            true
        else
            false
        end
    else
        # Legacy message-count based compacting
        current_msg_count >= age_tracker.max_history
    end

    if should_compact
        keep = age_tracker.cut_to - (conv.messages[end - age_tracker.cut_to + 1].role === :assistant)

        do_compact!(age_tracker, conv, keep)

        # Clean up old source trackers
        min_age = age_tracker.age - age_tracker.cut_to
        sources_to_delete = String[]
        for (source, age) in age_tracker.tracker
            if age < min_age
                push!(sources_to_delete, source)
            end
        end
        for (; tracker_context, changes_tracker) in contexts
            cut_old_sources!(sources_to_delete, tracker_context, changes_tracker)
        end
        for source in sources_to_delete
            delete!(age_tracker.tracker, source)
        end
    end
    age_tracker.last_message_count = length(conv.messages)
    return false
end

function get_cache_setting(tracker::AgeTracker, conv::Session)
    context_limit = get_effective_context_limit(tracker)

    if context_limit > 0
        # Context-based: check if we're near the threshold (within 5% of trigger)
        current_tokens = estimate_context_tokens(tracker, conv)
        near_threshold = context_limit * (tracker.compact_threshold - 0.05)
        if current_tokens >= near_threshold
            @info "We do not cache, because next message may trigger compacting!" current_tokens near_threshold
            return :all_but_last
        end
    else
        # Legacy message-count based
        messages_count = length(conv.messages)
        if messages_count >= tracker.max_history - 1
            @info "We do not cache, because next message will trigger a cut!"
            return :all_but_last
        end
    end
    return :all
end

"""
    force_compact!(age_tracker::AgeTracker, conv::Session; keep=nothing) -> String

Explicitly trigger conversation compaction regardless of message count.
Useful for manual "/compact" command or when context feels bloated.
Returns the generated summary.
"""
function force_compact!(age_tracker::AgeTracker, conv::Session; keep=nothing)
    keep = something(keep, age_tracker.cut_to)
    summary = do_compact!(age_tracker, conv, keep)
    !isempty(summary) && @info "Conversation compacted" kept=length(conv.messages) summary_length=length(summary)
    return summary
end

"""
    context_usage_stats(tracker::AgeTracker, conv::Session) -> NamedTuple

Get current context usage statistics for debugging/monitoring.
Returns a NamedTuple with current tokens, limit, threshold, percentage used, etc.
"""
function context_usage_stats(tracker::AgeTracker, conv::Session)
    context_limit = get_effective_context_limit(tracker)
    current_tokens = estimate_context_tokens(tracker, conv)
    threshold_tokens = context_limit > 0 ? context_limit * tracker.compact_threshold : 0

    (
        current_tokens = current_tokens,
        context_limit = context_limit,
        threshold_tokens = round(Int, threshold_tokens),
        percentage_used = context_limit > 0 ? round(100 * current_tokens / context_limit; digits=1) : 0.0,
        messages_count = length(conv.messages),
        will_compact = context_limit > 0 ? current_tokens >= threshold_tokens : length(conv.messages) >= tracker.max_history,
        mode = context_limit > 0 ? :context_based : :message_count_based
    )
end
