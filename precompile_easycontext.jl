
using EasyContext: Workspace
using EasyContext: format_shell_results_to_context
using EasyContext: greet, Context
using EasyContext: update_last_user_message_meta
using EasyContext: add_error_message!
using EasyContext: wait_user_question, reset!
using EasyContext: workspace_ctx_2_string, julia_ctx_2_string, shell_ctx_2_string
using EasyContext: ChangeTracker, AgeTracker
using EasyContext: CodeBlockExtractor
using EasyContext: BM25IndexBuilder, EmbeddingIndexBuilder
using EasyContext: ReduceRankGPTReranker, QuestionCTX
using EasyContext: print_project_tree
using EasyContext: context_combiner!
using EasyContext: extract_and_preprocess_codeblocks
using EasyContext: LLM_conditonal_apply_changes
using EasyContext: workspace_format_description
using EasyContext: shell_format_description
using EasyContext: julia_format_description
using EasyContext: get_cache_setting
using EasyContext: FullFileChunker
using EasyContext: codeblock_runner
using EasyContext: OpenAIBatchEmbedder
using EasyContext: JuliaLoader, JuliaSourceChunker, SourceChunker
using EasyContext


user_question="say a simple yes"
project_paths=["./test"]
logdir=joinpath(@__DIR__, "..", "conversations")
show_tokens=false
silent=false
loop=false
# init
workspace       = Workspace(project_paths)
workspace_ctx   = Context()
ws_age!         = AgeTracker()
changes_tracker      = ChangeTracker()
ws_simi_filterer = create_combined_index_builder(top_k=30)


julia_pkgs      = JuliaLoader()
julia_ctx       = Context()
jl_age!         = AgeTracker()
changes_tracker      = ChangeTracker()
jl_simi_filter = create_combined_index_builder(top_k=30)

reranker_filterer   = ReduceRankGPTReranker(batch_size=30, model="gpt4om")

extractor       = CodeBlockExtractor()
persister       = PersistableState(logdir)

question_acc    = QuestionCTX()

sys_msg         = ""
sys_msg        *= workspace_format_description()
sys_msg        *= shell_format_description()
sys_msg        *= julia_format_description()
conv_ctx        = ConversationCTX_from_sysmsg(sys_msg=sys_msg)


# prepare 
print_project_tree(workspace, show_tokens=show_tokens)

!silent && isempty(user_question) && (isdefined(Base, :active_repl) ? println("Your first [Enter] will just interrupt the REPL line and get into the conversation after that: ") : println("Your multiline input (empty line to finish):"))

_add_error_message!(msg) = add_error_message!(conv_ctx, msg)

# forward
while loop || !isempty(user_question)
	global user_question
	user_question   = isempty(user_question) ? wait_user_question(user_question) : user_question
	!silent && println("Thinking...")  # Only print if not silent

	ctx_question    = user_question |> question_acc 
	ctx_shell       = extractor |> shell_ctx_2_string #format_shell_results_to_context(extractor.shell_results)
	ctx_codebase    = begin 
		file_chunks = workspace(FullFileChunker()) 
		if isempty(file_chunks)
			""  
		else
			file_chunks_selected = ws_simi_filterer(file_chunks, ctx_question)
			file_chunks_reranked = reranker_filterer(file_chunks_selected, ctx_question)
			merged_file_chunks   = workspace_ctx(file_chunks_reranked)
			ws_age!(merged_file_chunks, max_history=5)
			state, scr_content   = changes_tracker(merged_file_chunks)
			workspace_ctx_2_string(state, scr_content)
		end
	end
	# ctx_jl_pkg      = begin
	#   file_chunks = julia_pkgs(SourceChunker())
	#   if isempty(file_chunks)
	#     ""
	#   else
	#     # entr_tracker()
	#     file_chunks_selected = jl_simi_filter(file_chunks, ctx_question)
	#     file_chunks_reranked = reranker_filterer(file_chunks_selected, ctx_question)
	#     merged_file_chunks   = julia_ctx(file_chunks_reranked)
	#     jl_age!(merged_file_chunks, max_history=5)
	#     state, scr_content   = changes_tracker(merged_file_chunks)
	#     julia_ctx_2_string(state, scr_content)
	#   end
	# end
	# @show ctx_jl_pkg
	query = context_combiner!(user_question, ctx_shell, ctx_codebase, )

	conversation  = conv_ctx(create_user_message(query))

	reset!(extractor)
	user_question = ""


	cache = get_cache_setting(conv_ctx)
	error = llm_solve(conversation, cache;
										on_text     = (text)   -> extract_and_preprocess_codeblocks(text, extractor, preprocess=(cb)->LLM_conditonal_apply_changes(cb)),
										on_meta_usr = (meta)   -> update_last_user_message_meta(conv_ctx, meta),
										on_meta_ai  = (ai_msg) -> (conv_ctx(ai_msg); to_disk!()),
										on_done     = ()       -> codeblock_runner(extractor),
										on_error    = (error)  -> ((user_question = "ERROR: $error"); to_disk!()),
	)

	silent && break
end