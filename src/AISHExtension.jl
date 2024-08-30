using Dates
using AISH: AbstractContextCreator, start, main, cut_history!, get_project_files, format_file_content
using AISH: curr_conv, SYSTEM_PROMPT, Message, save_user_message
import AISH

@kwdef struct EasyContextCreator <: AbstractContextCreator
  keep::Int=10
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

AISH.create_conversation!(ctx::EasyContextCreator, ai_state, question) = begin
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
  
  new_user_msg = Message(timestamp=now(), role=:user, content="""## User message:
  $(question)
  
  ## Additional context:
  $(context_msg)""")
  push!(conv.messages, new_user_msg)

  save_user_message(ai_state, new_user_msg)
end
