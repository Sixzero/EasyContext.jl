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
const DIFF_FILE = joinpath(@__DIR__, "..", "..", "data", "instant_apply_diffs.jld2")

function log_instant_apply(original::String, proposed::String, filepath::String, question::String="")
    atomic_append_diff(InstantApplyDiff(; original, proposed, filepath, question))
end

function log_instant_apply(extractor::CodeBlockExtractor, question::String, ws)
    @async_showerr for (_, task) in extractor.shell_scripts
        cb = fetch(task)
        log_instant_apply(cb, question, ws)
    end
end
function log_instant_apply(cb::CodeBlock, question::String, ws)
    original_content = cd(ws.root_path) do
        default_source_parser(cb.file_path, "")
    end
    cb.type == :MODIFY && log_instant_apply(original_content, cb.pre_content, cb.file_path, question)
end

function get_next_diff_number(file)
    !haskey(file, "diffs") && return 1
    
    # Extract numbers from diff_X keys CUT: diff_

    numbers = [Base.parse(Int, key[6:end]) 
               for key in keys(file["diffs"])]
    
    return isempty(numbers) ? 1 : maximum(numbers) + 1
end

function atomic_append_diff(diff::InstantApplyDiff)
    @async_showerr lock(DIFF_LOCK) do
        mkpath(dirname(DIFF_FILE))
        success = false
        jldopen(DIFF_FILE, "a+") do file
            group = !haskey(file, "diffs") ? JLD2.Group(file, "diffs") : file["diffs"]
            next_num = get_next_diff_number(file)
            @show next_num
            group["diff_$next_num"] = diff
            success = true
        end
        success || @warn "Failed to append diff to $DIFF_FILE"
        return success
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

function load_instant_apply_diffs()
    !isfile(DIFF_FILE) && return InstantApplyDiff[]
    JLD2.load(DIFF_FILE, typemap=Dict("Reconstruct@EasyContext.InstantApplyDiff" => LegacyInstantApplyDiff))
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
        evals = if isfile(MODEL_COMPARISON_FILE)
            JLD2.load(MODEL_COMPARISON_FILE)
        else
            Dict{String, MergeEvaluation}()
        end
        evals[key] = eval
        JLD2.save(MODEL_COMPARISON_FILE, evals)
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


