context_combiner(contexts::Vector{String}) = """$(join(contexts, "\n\n"))"""
function context_combiner!(user_question, context::String)
  """
  $context
  <UserQuestion>
  $user_question
  </UserQuestion>"""
end


function context_combiner!(user_question, contexts::Dict{String,String}, verbose=true)
  is_there_base64 = any(p -> startswith(p.first, "base64img_"), contexts)
  if is_there_base64
    verbose && @warn "There is a base64 image in the context, might be a sign of a problem" stacktrace()
    context_combiner!(user_question, context_combiner(collect(values(filter(p -> !startswith(p.first, "base64img_"), contexts)))))
  else
    context_combiner!(user_question, context_combiner(collect(values(contexts))))
  end
end