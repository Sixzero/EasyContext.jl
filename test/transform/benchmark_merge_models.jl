using Test
using EasyContext
using PromptingTools
using JLD2
using Dates
using Statistics
using EasyContext: apply_changes_to_file, save_merge_evaluation
using EasyContext: load_instant_apply_diffs, MODEL_COMPARISON_FILE, MergeEvaluation, generate_comparison_key
using DataFrames, PrettyTables
using EasyContext: get_merge_prompt_v2

function benchmark_merge_models(configs)
    
    # Load existing evaluations
    evaluations = isfile(MODEL_COMPARISON_FILE) ? JLD2.load(MODEL_COMPARISON_FILE) : Dict{String, MergeEvaluation}()

    diffs_group::Dict{String, Any} = load_instant_apply_diffs() # most of the time it is String => InstantApplyDiff
    
    for (diff_key, diff) in diffs_group
        asyncmap(configs) do config
            eval_key = generate_comparison_key(diff_key; config)
            
            if !occursin("v2", eval_key) && haskey(evaluations, eval_key)
                println("Skipping $eval_key (already evaluated)")
                return
            end
            
            println("Processing $eval_key")
            time = @elapsed merged = apply_changes_to_file(diff.original, diff.proposed; config..., verbose=false)
            
            eval = MergeEvaluation(
                diff_key=diff_key,
                merged=merged,
                config=config,
                duration=time
            )
            save_merge_evaluation(eval_key, eval)
        end
    end
    
end

configs = [
    # (;model="oro1m", temperature=0),
    (;model="ggemma9", temperature=0),
    # (;model="mistrals", temperature=0),
    # (;model="mistralm", temperature=0),
    # (;model="mistrall", temperature=0),
    # (;model="mistralc", temperature=0),
    (;model="tqwen2p5_72B", temperature=0),
    (;model="tqwen2p5_7B", temperature=0),
    (;model="grok", temperature=0),
    # (;model="fqwen32B", temperature=0),
    # (;model="fqwen72B", temperature=0),
    (;model="gpt4o", temperature=0),
    (;model="gpt4om", temperature=0),
    (;model="orgf8b", temperature=0),
    (;model="orgf", temperature=0),
    # (;model="cl70", temperature=0, get_merge_prompt=get_merge_prompt_v2),
    (;model="cl70", temperature=0),
    (;model="claude", temperature=0),
    (;model="claudeh", temperature=0),
]
# Run benchmark if this is the main script
benchmark_merge_models(configs)
#%%
function printings(configs)
    # Load final results for reporting
    evaluations = JLD2.load(MODEL_COMPARISON_FILE)
    diffs_group::Dict{String, Any} = load_instant_apply_diffs()

    for (diff_key, diff) in diffs_group
        searched_key = diff_key * ":claude&t=0"
        if !haskey(evaluations, searched_key)
            continue
        end
        for config in configs
            eval_key = generate_comparison_key(diff_key; config)
            eval = evaluations[eval_key]
            println("  Task $(eval_key): $(length(eval.merged)) chars")
        end
    end
end
printings(configs)
#%%
function export_merge_results(diff_key::String, configs)
    evaluations = JLD2.load(MODEL_COMPARISON_FILE)
    
    for config in configs
        eval_key = generate_comparison_key(diff_key; config)
        haskey(evaluations, eval_key) || continue
        
        # Sanitize filename by replacing : and & with _
        filename = replace(eval_key, [':','&'] => '_') * ".txt"
        write(String(@__DIR__) * "/" * filename, string(evaluations[eval_key].merged))
    end
end
export_merge_results("diffs/diff_12", configs)
export_merge_results("diffs/diff_19", configs)
#%%

evaluations = JLD2.load(MODEL_COMPARISON_FILE)
diffs_group::Dict{String, Any} = load_instant_apply_diffs()
println(diffs_group["diffs/diff_12"].original)
println(diffs_group["diffs/diff_12"].proposed)

#%%
function scoring_report(configs)
    evaluations = JLD2.load(MODEL_COMPARISON_FILE)
    diffs_group = load_instant_apply_diffs()
    
    scores = Dict{String,Float64}()
    counts = Dict{String,Int}()
    times = Dict{String,Vector{Float64}}()
    
    for (diff_key, _) in diffs_group
        reference_key = diff_key * ":claude&t=0"
        haskey(evaluations, reference_key) || continue
        
        reference = evaluations[reference_key].merged
        ref_len = length(reference)
        
        for config in configs
            eval_key = generate_comparison_key(diff_key; config)
            haskey(evaluations, eval_key) || continue
            
            eval = evaluations[eval_key]
            len_diff = abs(length(eval.merged) - ref_len)
            score = len_diff ≤ 4 ? 1.0 : 0.0
            
            model_key = split(eval_key, ":")[2]
            scores[model_key] = get(scores, model_key, 0.0) + score
            counts[model_key] = get(counts, model_key, 0) + 1
            push!(get!(times, model_key, Float64[]), eval.duration)
        end
    end
    
    # Create DataFrame for sorted results
    df = DataFrame(
        Model = String[],
        Accuracy = Float64[],
        Count = Int[],
        Mean_Time = Float64[],
        Median_Time = Float64[],
        Std_Time = Float64[]
    )
    
    for (model, total_score) in sort(collect(scores), by=x->x[2]/counts[x[1]], rev=true)
        n = counts[model]
        model_times = times[model]
        push!(df, (
            model,
            total_score / n * 100,
            n,
            mean(model_times),
            median(model_times),
            std(model_times)
        ))
    end
    
    println("\nModel Performance Summary (compared to claude&t=0):")
    pretty_table(df, 
        formatters = (
            ft_printf("%.1f%%", 2),
            ft_printf("%.2fs", 4),
            ft_printf("%.2fs", 5),
            ft_printf("%.2fs", 6)
        ),
        crop = :none
    )
end

# Add after your existing benchmark run:
scoring_report(configs)

