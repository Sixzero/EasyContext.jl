context_combiner(contexts::Vector{String}) = """$(join(contexts, "\n\n"))"""
context_combiner!(user_question, context::String)   = """
$context
<UserQuestion>
$user_question
</UserQuestion>"""
context_combiner!(user_question, contexts::Dict{String,String}) = context_combiner!(user_question, context_combiner(collect(values(contexts))))
