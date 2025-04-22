const colors = Dict{Symbol, Symbol}(
    :NEW       => :blue,
    :UPDATED   => :yellow,
    :UNCHANGED => :light_black,
    :DELETED   => :red,
)

@kwdef mutable struct ChangeTracker{T}
    changes::OrderedDict{String, Symbol} = OrderedDict{String, Symbol}()
    chunks_dict::OrderedDict{String, T} = OrderedDict{String, T}()
    verbose::Bool = true
end


function update_changes!(tracker::ChangeTracker, ctx::Context)
    d = update_changes!(tracker, ctx.d)
    return ctx
end

function update_changes!(tracker::ChangeTracker, ctx::AbstractDict{String, T}) where {T <: Union{AbstractChunk, AbstractString}}
    current_keys = keys(ctx)
    deleted_keys = [k for k in keys(tracker.changes) if !(k in current_keys)]
    for k in deleted_keys
        delete!(tracker.changes, k)
        delete!(tracker.chunks_dict, k)
    end
    
    for (source, _) in tracker.changes # we reset everything to :UNCHANGED
        tracker.changes[source] != :UNCHANGED && (tracker.changes[source] = :UNCHANGED)
    end

    for (source, chunk) in ctx
        if !haskey(tracker.changes, source)
            tracker.changes[source] = :NEW
            tracker.chunks_dict[source] = chunk
            continue
        end
        if need_source_reparse(chunk)
            new_chunk = reparse_chunk(chunk)
            if tracker.chunks_dict[source] == new_chunk
                tracker.changes[source] = :UNCHANGED
            else
                tracker.changes[source] = :UPDATED
                tracker.chunks_dict[source] = new_chunk
                ctx[source]                 = new_chunk
            end
        end
    end
    tracker.verbose && print_context_updates(tracker; deleted=deleted_keys, item_type="sources")
    return ctx
end
function get_filtered_chunks(tracker::ChangeTracker, ctx::Context)
    new_chunks = [v for (k, v) in ctx.d if tracker.changes[k] == :NEW]
    updated_chunks = [v for (k, v) in ctx.d if tracker.changes[k] == :UPDATED]
    return new_chunks, updated_chunks
end

function serialize(tag::String, element::String, new_chunks::Vector, updated_chunks::Vector)
    output = ""
    
    new_files = join([string(chunk) for chunk in new_chunks], '\n')
    if !is_really_empty(new_files)
        output *= """
        <$tag NEW>
        $new_files
        </$tag>
        """
    end
    
    updated_files = join([string(chunk) for chunk in updated_chunks], '\n')
    if !is_really_empty(updated_files)
        output *= """
        <$tag UPDATED>
        $updated_files
        </$tag>
        """
    end
    
    return output
end

function print_context_updates(tracker::ChangeTracker; deleted, item_type::String="files")
    
    printstyled("Number of $item_type selected: ", color=:green, bold=true)
    printstyled(length(tracker.changes), "\n", color=:green)
    
    for (item, s) in tracker.changes
        printstyled("  [$s] $item\n", color=colors[s])
    end
    for item in deleted
        printstyled("  [DELETED] $item\n", color=colors[:DELETED])
    end
end


