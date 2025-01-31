context_combiner(contexts::Vector{String}) = """$(join(contexts, "\n\n"))"""
function context_combiner!(user_question, context::String)
  """
  $context
  <UserQuestion>
  $user_question
  </UserQuestion>"""
end
context_combiner!(user_question, contexts::Dict{String,String}) = context_combiner!(user_question, context_combiner(collect(values(contexts))))
