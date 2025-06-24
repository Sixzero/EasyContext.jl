context_combiner(contexts::Vector{String}) = """$(join(contexts, "\n\n"))"""
function context_combiner!(user_question, context::String)
  """
  $context
  <UserQuestion>
  $user_question
  </UserQuestion>"""
end

# Helper function to check if a string is a data URL (base64 encoded content)
is_data_url(s::AbstractString) = startswith(s, "data:")

function context_combiner!(user_question, contexts::Dict{String,String}, verbose=true)
  is_there_base64 = any(p -> startswith(p.first, "base64img_"), contexts)
  is_there_data_url = any(p -> is_data_url(p.second), contexts)
  
  if is_there_base64 || is_there_data_url
    verbose && @warn "There is base64/data URL content in the context, filtering it out" stacktrace()
    filtered_contexts = filter(p -> !startswith(p.first, "base64img_") && !is_data_url(p.second), contexts)
    context_combiner!(user_question, context_combiner(collect(values(filtered_contexts))))
  else
    context_combiner!(user_question, context_combiner(collect(values(contexts))))
  end
end