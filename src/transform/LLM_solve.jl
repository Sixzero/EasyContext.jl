

function LLM_solve(conv, cache; model::String="claude-3-5-sonnet-20240620", on_meta_usr=noop, on_text=noop, on_meta_ai=noop, on_error=noop, on_done=noop, on_start=noop)
	channel = ai_stream(conv, model=model, printout=false, cache=cache)
	try
		process_stream(channel; 
				on_text     = (text) -> begin
						on_text(text)
						print(text)
				end,
				on_meta_usr = (meta) -> begin
						on_meta_usr(meta)
						println("\e[32mUser message: \e[0m$(Anthropic.format_meta_info(meta))")
						print("\e[36m¬ \e[0m")
				end,
				on_meta_ai  = (meta, full_msg) -> begin
						on_meta_ai(create_AI_message(full_msg, meta))
						println("\n\e[32mAI message: \e[0m$(Anthropic.format_meta_info(meta))")
				end,
				on_error,
				on_done,
				on_start)


		return nothing
	catch e
		@error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
		on_error(error)
		return e
	end

end

