using JLD2, Dates, Base.Threads

export log_instant_apply, delete_merge_evaluation

@kwdef struct InstantApplyDiff
    original::String
    proposed::String
    filepath::String
    question::String
    timestamp::DateTime = now()
end

const DIFF_LOCK = ReentrantLock()
const DEFAULT_DIFF_FILE = joinpath(@__DIR__, "..", "..", "data", "instant_apply_diffs.jld2")

function log_instant_apply(original::String, proposed::String, filepath::String, question::String="")
    atomic_append_diff(InstantApplyDiff(; original, proposed, filepath, question))
end

function log_instant_apply(extractor::ToolTagExtractor, question::String)
    @async_showerr for (_, task) in extractor.tool_tasks
        cb = fetch(task)
        log_instant_apply(cb, question)
    end
end
log_instant_apply(cb, question) = nothing
function log_instant_apply(cb::ModifyFileTool, question::String)
    original_content = cd(cb.root_path) do
        reparse_chunk(FileChunk(source=SourcePath(path=cb.file_path))).content
    end
    log_instant_apply(original_content, cb.content, cb.file_path, question)
end

function get_next_diff_number(file)
    !haskey(file, "diffs") && return 1
    
    # Extract numbers from diff_X keys CUT: diff_

    numbers = [Base.parse(Int, key[6:end]) 
               for key in keys(file["diffs"])]
    
    return isempty(numbers) ? 1 : maximum(numbers) + 1
end

function atomic_append_diff(diff::InstantApplyDiff, diff_file::String=DEFAULT_DIFF_FILE)
    @async_showerr lock(DIFF_LOCK) do
        mkpath(dirname(diff_file))
        success = false
        jldopen(diff_file, "a+") do file
            group = !haskey(file, "diffs") ? JLD2.Group(file, "diffs") : file["diffs"]
            next_num = get_next_diff_number(file)
            group["diff_$next_num"] = diff
            success = true
        end
        success || @warn "Failed to append diff to $diff_file"
        return success
    end
end

function save_instant_apply_diffs(diffs::Dict{String,InstantApplyDiff}, diff_file::String=DEFAULT_DIFF_FILE)
    lock(DIFF_LOCK) do
        mkpath(dirname(diff_file))
        JLD2.save(diff_file, diffs)
    end
end

# Legacy struct for backwards compatibility
@kwdef struct LegacyInstantApplyDiff
    original::String
    proposed::String
    filepath::String
    timestamp::DateTime = now()
end

function Base.convert(::Type{InstantApplyDiff}, x::LegacyInstantApplyDiff)
    InstantApplyDiff(
        original=x.original,
        proposed=x.proposed,
        filepath=x.filepath,
        question="", # Default empty string for legacy entries
        timestamp=x.timestamp
    )
end

function load_instant_apply_diffs(diff_file::String=DEFAULT_DIFF_FILE)
    !isfile(diff_file) && return Dict{String,InstantApplyDiff}()
    diffs = lock(DIFF_LOCK) do
        JLD2.load(diff_file, typemap=Dict("Reconstruct@EasyContext.InstantApplyDiff" => LegacyInstantApplyDiff))
    end

    result = Dict{String,InstantApplyDiff}()
    for (k, v) in diffs
        if v isa JLD2.ReconstructedMutable{:InstantApplyDiff}
            result[k] = InstantApplyDiff(
                original=v.original,
                proposed=v.proposed,
                filepath=v.filepath,
                question="",  # Legacy entries have no question
                timestamp=v.timestamp
            )
        elseif v isa LegacyInstantApplyDiff
            result[k] = convert(InstantApplyDiff, v)
        else
            result[k] = v
        end
    end
    return result
end

@kwdef struct MergeEvaluation
    diff_key::String
    merged::String
    config::NamedTuple
    duration::Float64 = 0.0
end

const MODEL_COMPARISON_FILE = joinpath(@__DIR__, "..", "..", "data", "instant_apply_merges.jld2")

function generate_comparison_key(diff_key::String; config::NamedTuple)
    generate_comparison_key(diff_key, config)
end

function generate_comparison_key(diff_key::String, config::NamedTuple{(:model,)})
    "$diff_key:$(config.model)"
end

function generate_comparison_key(diff_key::String, config::NamedTuple{(:model, :temperature)})
    "$diff_key:$(config.model)&t=$(config.temperature)"
end

function generate_comparison_key(diff_key::String, config::NamedTuple{(:model, :temperature, :get_merge_prompt)})
    prompt_version = get_merge_prompt_v1 === config.get_merge_prompt ? "v1" : get_merge_prompt_v2 === config.get_merge_prompt ? "v2" : nothing
    @assert prompt_version !== nothing "Unknown prompt version"
    "$diff_key:$(config.model)&t=$(config.temperature)&p=$(prompt_version)"
end

function save_merge_evaluation(key::String, eval::MergeEvaluation)
    lock(DIFF_LOCK) do
        mkpath(dirname(MODEL_COMPARISON_FILE))
        success = false
        
        # Create file if it doesn't exist
        !isfile(MODEL_COMPARISON_FILE) && JLD2.save(MODEL_COMPARISON_FILE, Dict{String,MergeEvaluation}())
        
        # Open in read/write mode and update
        jldopen(MODEL_COMPARISON_FILE, "r+") do file
            haskey(file, key) && delete!(file, key)  # Delete if exists
            file[key] = eval
            success = true
        end
        
        success || @warn "Failed to save merge evaluation for key: $key"
        return success
    end
end

function delete_merge_evaluation(key::String)
    lock(DIFF_LOCK) do
        !isfile(MODEL_COMPARISON_FILE) && return
        evals = JLD2.load(MODEL_COMPARISON_FILE)
        haskey(evals, key) || return
        delete!(evals, key)
        JLD2.save(MODEL_COMPARISON_FILE, evals)
    end
end
