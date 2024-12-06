using EasyContext
using PrecompileTools
using DataStructures: OrderedDict

@setup_workload begin
    # Dummy values for testing
    user_question = "How do I encode a string to Base64?"
    project_paths = ["."]
    logdir = tempdir()
    show_tokens = false

    # Create minimal dummy file chunks for testing
    dummy_chunks = OrderedDict(
        "src/test.jl" => "function hello() println(\"Hello\") end",
        "src/main.jl" => "using Test\ninclude(\"test.jl\")"
    )

    # Mock AI function that doesn't make API calls
    mock_ai_fn(prompt; kwargs...) = PromptingTools.AIMessage("1,2")

    @time "Precompilation EasyContext.jl" @compile_workload begin
        # Initialize workspace context
        workspace_context = init_workspace_context(project_paths, verbose=false)
               
        # Test the filtering functionality with dummy data
        indexx = get_index(workspace_context.ws_simi_filterer, dummy_chunks)
        file_chunks_selected = workspace_context.ws_simi_filterer(indexx, user_question)
        file_chunks_reranked = rerank(workspace_context.ws_reranker_filterer, file_chunks_selected, user_question; ai_fn=mock_ai_fn)

        # EasyContext-specific initializations
        # workspace_context = init_workspace_context(project_paths, verbose=false)
        
        # # Use the minimal package scope for precompilation
        # julia_context = init_julia_context(package_scope=:minimal)
        
        # age_tracker = AgeTracker(max_history=14, cut_to=6)
        
        # question_acc = QuestionCTX()
        # persister = PersistableState(logdir)

        # # Simulate usage of EasyContext functions
        # # print_project_tree(workspace_context.workspace, show_tokens=show_tokens)
        
        # ctx_question = user_question |> question_acc 
        # ctx_shell = extractor |> shell_ctx_2_string
        # ctx_jl_pkg = process_julia_context(julia_context, ctx_question; age_tracker)
        
        
        # conv_ctx(create_user_message("Msg"))
        
        # reset!(extractor)
        
        # cache = get_cache_setting(age_tracker, conv_ctx)
        
        # # Simulate other EasyContext function usage
        # dummy_text = "This is a dummy response with a code block:
        # ```julia
        # using Base64
        # encoded = base64encode(\"Hello, World!\")
        # println(encoded)
        # ```"
        # extract_and_preprocess_codeblocks(dummy_text, extractor, preprocess=(cb)->LLM_conditional_apply_changes(cb))
        # conv_ctx(create_AI_message("Dummy AI message"))
        # codeblock_runner(extractor)
        
        # cut_old_conversation_history!(age_tracker, conv_ctx, julia_context, workspace_context)
    end
end
