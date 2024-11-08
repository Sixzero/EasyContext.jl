using JLD2
using DataFrames
using EasyContext: load_instant_apply_diffs, MODEL_COMPARISON_FILE, MergeEvaluation, generate_comparison_key
using PromptingTools
using EasyContext: save_merge_evaluation, InstantApplyDiff

"""
Compare outputs of two different model configurations and find cases where they differ.
Returns a Dict mapping diff_keys to the corresponding outputs from both models.
Also saves differing outputs to files in the 'compare' directory.
"""
function find_different_outputs(config1, config2; min_diff=4)
    evaluations = JLD2.load(MODEL_COMPARISON_FILE)
    diffs_group = load_instant_apply_diffs()
    
    differences = Dict{String, NamedTuple{(:output1, :output2), Tuple{String, String}}}()
    compare_dir = joinpath(@__DIR__, "compare")
    mkpath(compare_dir)
    
    for diff_key in keys(diffs_group)
        eval_key1 = generate_comparison_key(diff_key; config=config1)
        eval_key2 = generate_comparison_key(diff_key; config=config2)
        
        haskey(evaluations, eval_key1) || continue
        haskey(evaluations, eval_key2) || continue
        
        output1 = evaluations[eval_key1].merged
        output2 = evaluations[eval_key2].merged
        
        # Only collect if outputs differ by more than min_diff characters
        if abs(length(output1) - length(output2)) >= min_diff
            differences[diff_key] = (output1=output1, output2=output2)
            
            # Save to files for comparison
            diff_name = replace(diff_key, "/" => "_")
            write(joinpath(compare_dir, "$(diff_name)_$(config1.model)"), output1)
            write(joinpath(compare_dir, "$(diff_name)_$(config2.model)"), output2)
        end
    end
    
    return differences
end

function get_question_msg(eval::InstantApplyDiff) 
    return "```question\n$(eval.question)\n```"
end
get_question_msg(_) = ""
"""
Analyze differences between two model outputs using another model.
"""
function analyze_differences(differences::Dict, analysis_model="claude"; save_key="analysis")
    evaluations = isfile(MODEL_COMPARISON_FILE) ? JLD2.load(MODEL_COMPARISON_FILE) : Dict{String, MergeEvaluation}()
    diffs_group = load_instant_apply_diffs()
    
    for (diff_key, outputs) in differences
        eval_key = "$(diff_key):$(save_key)"
        eval = diffs_group[diff_key]
        question_msg = get_question_msg(eval)
        answer = aigenerate("""
        The task was to merge the <code> based on <update> where the update was generated to solve the question:
        $question_msg
        <code>
        $(eval.original)
        </code>
        <update>
        $(eval.proposed)
        </update>

        # Solutions
        I have two different AI models solving this task. The
        Please analyze the differences and determine which solution is better:

        # Solution 1:
        ```
        $(outputs.output1)
        ```

        # Solution 2:
        ```
        $(outputs.output2)
        ```

        # Task:
        Explain:
        1. What are the key differences between these solutions? In case it is just a few lines then please write out the differences, otherwise just explain.
        2. Which solution appears to be better and why? Which one solves the question the best?
        3. Are there any potential issues in either solution?
        """, model=analysis_model)
        
        println(" ======= ORIGINAL")
        println(eval.original)
        println(" ======= PROPOSED")
        println(eval.proposed)
        println(" ======= COMPARISON")
        println(answer.content)
        println(" ======= ENDE")
        # eval = MergeEvaluation(
        #     diff_key=diff_key,
        #     merged=answer.content,
        #     config=(model=analysis_model, temperature=temperature),
        #     duration=answer.elapsed
        # )
        # save_merge_evaluation(eval_key, eval)
    end
end

# Example usage:
if true  # Prevent running on include
    config1 = (model="claude", temperature=0)
    config2 = (model="orgf", temperature=0)
    # config2 = (model="gpt4o", temperature=0)
    # config2 = (model="tqwen2p5_72B", temperature=0)
    config2 = (;model="cl70", temperature=0)
    config2 = (;model="gpt4om", temperature=0)
    # config2 = (;model="cl70", temperature=0, get_merge_prompt=get_merge_prompt_v2),
    
    
    # Find differences
    differences = find_different_outputs(config1, config2)
    println("Found $(length(differences)) different outputs")
    
    # Analyze differences
    analyze_differences(differences)
    
    # Print analyses
    evaluations = JLD2.load(MODEL_COMPARISON_FILE)
    for diff_key in keys(differences)
        eval_key = "$(diff_key):analysis"
        if haskey(evaluations, eval_key)
            println("\n=== Analysis for $diff_key ===")
            println(evaluations[eval_key].merged)
        end
    end
end
