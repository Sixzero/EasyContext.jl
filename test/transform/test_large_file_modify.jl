using Test
using EasyContext
using EasyContext: CodeBlock, LLM_conditonal_apply_changes

#%%
@testset "Large file modification test" begin
    # Create a temporary large file
    temp_dir = mktempdir()
    large_file_path = joinpath(temp_dir, "large_file.jl")
    
    # Generate a large file with dummy content (>20k chars)
    large_content = join(["""
    function dummy_function_$(i)(x::Int)
        # This is a dummy function number $i
        result = x + $i
        # Some more dummy comments
        # to make the file larger
        # and more realistic
        return result
    end
    """ for i in 1:150], "\n\n")
    
    original_lines = count("\n", large_content)
    write(large_file_path, large_content)
    original_content = read(large_file_path, String)


    # @testset "Small file append" begin
    #     # Create a small modification to add at the end
    #     modification = """// ... existing code ...

    #     function log_processing_info(data)
    #         @info "Processing data with \$(length(data)) elements"
    #         @info "Start time: \$(now())"
    #     end
    #     """
        
    #     # Create CodeBlock for modification
    #     cb = CodeBlock(;
    #         type=:MODIFY,
    #         language="julia",
    #         file_path=large_file_path,
    #         content=modification,
    #         root_path=temp_dir
    #     )
        
    #     # Apply the changes - this should only propose the changes in postcontent
    #     @time modified_cb = LLM_conditonal_apply_changes(cb)
        
    #     # Count lines in proposed content
    #     proposed_lines = count("\n", modified_cb.postcontent)
        
    #     # Tests for postcontent (proposed changes)
    #     @test modified_cb.postcontent != cb.content  # Proposed content is different from modification
    #     @test modified_cb.postcontent != small_content  # Proposed content is different from original
    #     @test occursin("function dummy_function_1(x::Int)", modified_cb.postcontent)  # Check start preserved
    #     @test occursin("function dummy_function_100(x::Int)", modified_cb.postcontent)  # Check last function preserved
    #     @test occursin("function log_processing_info(data)", modified_cb.postcontent)  # Check new content added
    #     @test occursin("@info \"Processing data with \$(length(data)) elements\"", modified_cb.postcontent)  # Check new content details
        
    #     # Check line count difference (should be exactly 5-7 new lines: empty line + function + 2 info lines + end)
    #     expected_new_lines_min, expected_new_lines_max = 5, 7
    #     @test original_lines + expected_new_lines_min < proposed_lines < original_lines + expected_new_lines_max
    # end
    @testset "Append at end" begin
        # Create a small modification to add at the end
        modification = """// ... existing code ...

        function log_processing_info(data)
            @info "Processing data with \$(length(data)) elements"
            @info "Start time: \$(now())"
        end
        """
        
        # Create CodeBlock for modification
        cb = CodeBlock(;
            type=:MODIFY,
            language="julia",
            file_path=large_file_path,
            content=modification,
            root_path=temp_dir
        )
        
        # Apply the changes - this should only propose the changes in postcontent
        @time modified_cb = LLM_conditonal_apply_changes(cb)
        
        # Count lines in proposed content
        proposed_lines = count("\n", modified_cb.postcontent)
        
        # Tests for postcontent (proposed changes)
        @test modified_cb.postcontent != cb.content  # Proposed content is different from modification
        @test modified_cb.postcontent != large_content  # Proposed content is different from original
        @test occursin("function dummy_function_1(x::Int)", modified_cb.postcontent)  # Check start preserved
        @test occursin("function dummy_function_100(x::Int)", modified_cb.postcontent)  # Check last function preserved
        @test occursin("function log_processing_info(data)", modified_cb.postcontent)  # Check new content added
        @test occursin("@info \"Processing data with \$(length(data)) elements\"", modified_cb.postcontent)  # Check new content details
        
        # Check line count difference (should be exactly 5-7 new lines: empty line + function + 2 info lines + end)
        expected_new_lines_min, expected_new_lines_max = 5, 7
        @test original_lines + expected_new_lines_min <= proposed_lines <= original_lines + expected_new_lines_max
    end

    @testset "Insert after specific function" begin
        # Create a modification to insert after dummy_function_123
        modification = """
        // function dummy_function_123(x::Int) is here
        # Insert the new function here
        function process_result(x::Int)
            result = dummy_function_123(x)
            @info "Processing result: \$result"
            return result * 2
        end
        // ... existing code ..."""
        
        cb = CodeBlock(;
            type=:MODIFY,
            language="julia",
            file_path=large_file_path,
            content=modification,
            root_path=temp_dir
        )
        
        @time modified_cb = LLM_conditonal_apply_changes(cb)
        
        # Verify the changes
        @test occursin("function dummy_function_123(x::Int)", modified_cb.postcontent)
        @test occursin("function process_result(x::Int)", modified_cb.postcontent)
        @test occursin("result = dummy_function_123(x)", modified_cb.postcontent)
        
        # Check function order
        dummy_123_pos = findfirst("function dummy_function_123", modified_cb.postcontent)
        process_result_pos = findfirst("function process_result", modified_cb.postcontent)
        @test !isnothing(dummy_123_pos) && !isnothing(process_result_pos)
        @test dummy_123_pos < process_result_pos  # Ensure process_result comes after dummy_123
        dummy_124_pos = findfirst("function dummy_function_124", modified_cb.postcontent)
        @test process_result_pos < dummy_124_pos
        
        # Check that other functions are preserved
        @test occursin("function dummy_function_1(x::Int)", modified_cb.postcontent)
        @test occursin("function dummy_function_100(x::Int)", modified_cb.postcontent)
        @test occursin("function dummy_function_150(x::Int)", modified_cb.postcontent)
    end
    
    # Verify original file wasn't modified
    current_content = read(large_file_path, String)
    @test current_content == original_content
    
    # Cleanup
    rm(temp_dir, recursive=true)
end

#%%

modify = """
MODIFY 
```julia
function aiscan(prompt_schema::AbstractAnthropicSchema, prompt::ALLOWED_PROMPT_TYPE;
        verbose::Bool = true,
        api_key::String = ANTHROPIC_API_KEY,
        model::String = MODEL_CHAT,
        return_all::Bool = false, dry_run::Bool = false,
        conversation::AbstractVector{<:AbstractMessage} = AbstractMessage[],
        no_system_message::Bool = false,
        image_path::Union{Nothing, AbstractString, Vector{<:AbstractString}} = nothing,
        http_kwargs::NamedTuple = (retry_non_idempotent = true,
            retries = 5,
            readtimeout = 120), api_kwargs::NamedTuple = NamedTuple(),
        cache::Union{Nothing, Symbol} = nothing,
        betas::Union{Nothing, Vector{Symbol}} = nothing,
        kwargs...)
    ## Vision-specific functionality -- if `image_path` is provided, attach images to the latest user message
    @assert !isnothing(image_path) "aiscan requires an image_path to be provided!"
    prompt = attach_images_to_user_message(prompt; image_path, attach_to_latest = true)
    
    ## Use the aigenerate function with the updated prompt
    msg = aigenerate(prompt_schema, prompt;
        verbose, api_key, model, return_all, dry_run,
        conversation, no_system_message, http_kwargs, api_kwargs, cache, betas, kwargs...)
    return msg
end
```
"""
cb = CodeBlock(type=:MODIFY,
language="julia",
file_path="../PromptingTools.jl/src/llm_anthropic.jl",
content=modify,
root_path="."
)
@time modified_cb = LLM_conditonal_apply_changes(cb)
;