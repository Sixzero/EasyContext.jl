export SourceTracker, SourceInfo, register_source!, register_changes!, update_age!, touch_source!,
       get_sources_to_cut, get_sources_older_than, remove_sources!,
       get_total_tokens, get_source_tokens, get_source_age

"""
SourceInfo holds token count and recency for a single source.
"""
struct SourceInfo
    tokens::Int
    last_used::Int  # age when last referenced
end

"""
SourceTracker tracks sources with their token counts and recency.
Used by Cutters to decide which sources to remove when freeing up token budget.

Sources are tracked by:
- token count (how much context they use)
- last_used age (when they were last referenced)

When cutting, oldest sources are removed first until the token budget is met.
"""
@kwdef mutable struct SourceTracker
    sources::Dict{String, SourceInfo} = Dict{String, SourceInfo}()
    total_tokens::Int = 0
    current_age::Int = 0
    estimation_method::TokenEstimationMethod = CharCountDivTwo
end

"""
    register_source!(tracker::SourceTracker, source::String, content::AbstractString)

Register or update a source with its content. Calculates token count automatically.
"""
function register_source!(tracker::SourceTracker, source::String, content::AbstractString)
    tokens = estimate_tokens(content, tracker.estimation_method)

    # Update total: subtract old if exists, add new
    if haskey(tracker.sources, source)
        tracker.total_tokens -= tracker.sources[source].tokens
    end

    tracker.sources[source] = SourceInfo(tokens, tracker.current_age)
    tracker.total_tokens += tokens
    return tracker
end

"""
    register_source!(tracker::SourceTracker, source::String, tokens::Int)

Register or update a source with a pre-calculated token count.
"""
function register_source!(tracker::SourceTracker, source::String, tokens::Int)
    if haskey(tracker.sources, source)
        tracker.total_tokens -= tracker.sources[source].tokens
    end

    tracker.sources[source] = SourceInfo(tokens, tracker.current_age)
    tracker.total_tokens += tokens
    return tracker
end

"""
    register_changes!(tracker::SourceTracker, changes::ChangeTracker, ctx::Context)

Register sources from a ChangeTracker, updating token counts for NEW/UPDATED sources.
"""
function register_changes!(tracker::SourceTracker, changes::ChangeTracker, ctx::Context)
    register_changes!(tracker, changes, ctx.d)
end

function register_changes!(tracker::SourceTracker, changes::ChangeTracker, ctx::AbstractDict)
    for (source, state) in changes.changes
        if state === :NEW || state === :UPDATED
            if haskey(ctx, source)
                content = string(ctx[source])
                register_source!(tracker, source, content)
            end
        end
    end
    return tracker
end

"""
    update_age!(tracker::SourceTracker)

Increment the age counter. Call this after each conversation turn.
"""
function update_age!(tracker::SourceTracker)
    tracker.current_age += 1
    return tracker
end

"""
    touch_source!(tracker::SourceTracker, source::String)

Mark a source as recently used (update its last_used age).
"""
function touch_source!(tracker::SourceTracker, source::String)
    if haskey(tracker.sources, source)
        info = tracker.sources[source]
        tracker.sources[source] = SourceInfo(info.tokens, tracker.current_age)
    end
    return tracker
end

"""
    get_sources_to_cut(tracker::SourceTracker, tokens_to_free::Int) -> Vector{String}

Get list of sources to remove to free up at least `tokens_to_free` tokens.
Returns sources sorted by age (oldest first).
"""
function get_sources_to_cut(tracker::SourceTracker, tokens_to_free::Int)
    tokens_to_free <= 0 && return String[]

    # Sort sources by last_used (oldest first)
    sorted = sort(collect(tracker.sources), by = kv -> kv[2].last_used)

    sources_to_cut = String[]
    freed = 0

    for (source, info) in sorted
        freed >= tokens_to_free && break
        push!(sources_to_cut, source)
        freed += info.tokens
    end

    return sources_to_cut
end

"""
    get_sources_older_than(tracker::SourceTracker, min_age::Int) -> Vector{String}

Get all sources that haven't been used since `min_age`.
"""
function get_sources_older_than(tracker::SourceTracker, min_age::Int)
    return [source for (source, info) in tracker.sources if info.last_used < min_age]
end

"""
    remove_sources!(tracker::SourceTracker, sources::Vector{String})

Remove sources from the tracker.
"""
function remove_sources!(tracker::SourceTracker, sources::Vector{String})
    for source in sources
        if haskey(tracker.sources, source)
            tracker.total_tokens -= tracker.sources[source].tokens
            delete!(tracker.sources, source)
        end
    end
    return sources
end

"""
    remove_sources!(tracker::SourceTracker, sources::Vector{String}, contexts...)

Remove sources from tracker and from provided contexts.
Each context should be a NamedTuple with (context=, changes=) or (tracker_context=, changes_tracker=).
"""
function remove_sources!(tracker::SourceTracker, sources::Vector{String}, contexts...)
    remove_sources!(tracker, sources)

    for ctx in contexts
        if hasproperty(ctx, :context) && hasproperty(ctx, :changes)
            remove_from_context!(sources, ctx.context, ctx.changes)
        elseif hasproperty(ctx, :tracker_context) && hasproperty(ctx, :changes_tracker)
            remove_from_context!(sources, ctx.tracker_context, ctx.changes_tracker)
        end
    end

    return sources
end

function remove_from_context!(sources::Vector{String}, ctx::Context, ct::ChangeTracker)
    remove_from_context!(sources, ctx.d, ct)
end

function remove_from_context!(sources::Vector{String}, ctx::AbstractDict, ct::ChangeTracker)
    for source in sources
        delete!(ctx, source)
        delete!(ct.changes, source)
        delete!(ct.chunks_dict, source)
    end
end

"""
    get_total_tokens(tracker::SourceTracker) -> Int

Get the total tokens across all tracked sources.
"""
get_total_tokens(tracker::SourceTracker) = tracker.total_tokens

"""
    get_source_tokens(tracker::SourceTracker, source::String) -> Int

Get token count for a specific source. Returns 0 if not tracked.
"""
function get_source_tokens(tracker::SourceTracker, source::String)
    haskey(tracker.sources, source) ? tracker.sources[source].tokens : 0
end

"""
    get_source_age(tracker::SourceTracker, source::String) -> Int

Get the last_used age for a specific source. Returns -1 if not tracked.
"""
function get_source_age(tracker::SourceTracker, source::String)
    haskey(tracker.sources, source) ? tracker.sources[source].last_used : -1
end
