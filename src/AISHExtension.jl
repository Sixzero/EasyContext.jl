using Dates
using AISH: AbstractContextCreator, start, main, cut_history!, get_project_files, format_file_content
using AISH: curr_conv, SYSTEM_PROMPT, Message, format_shell_results
import AISH

@kwdef struct EasyContextCreator <: AbstractContextCreator
  keep::Int=10
end

function AISH.get_cache_setting(::EasyContextCreator)
    return nothing
end


get_context_for_question(question) = begin
  result = get_context(question)
  join(result.context, "\n")
end

function get_all_relevant_project_files(path, question)
    all_files = get_project_files(path)

    selected_files, fileindex = get_relevant_files(question, all_files)
    result = map(file -> format_file_content(file), selected_files)
    return join(result, "\n")
end

function get_relevant_codebase_files(question, path)
  """The relevant files from the codebase you are working on:
================================
$(get_all_relevant_project_files(path, question))
================================
This is the latest version of the codebase. Chats and later messages can only hold same or older versions of this. If something is not like chat ai messages proposed, that is probably because a change was not accepted, which usually has a reason.
"""
end

AISH.prepare_user_message!(ctx::EasyContextCreator, ai_state, question, shell_results) = begin
  conv = curr_conv(ai_state)
  
  # Create tasks for asynchronous execution
  codebase_task = @async get_relevant_codebase_files(question, conv.rel_project_paths)
  # context_task = @async get_context_for_question(question)
  
  # Wait for both tasks to complete
  codebase_ctx = fetch(codebase_task)
  # context_msg = fetch(context_task)
  context_msg = ""
  
  # Create system message
  conv.system_message = Message(timestamp=now(), role=:system, content=SYSTEM_PROMPT(ctx=codebase_ctx))
  
  cut_history!(conv, keep=ctx.keep)
  
  formatted_results = format_shell_results(shell_results)
  new_user_msg = """
  $formatted_results

  ## User message:
  $(question)
  
  ## Additional context:
  $(context_msg)"""
end
