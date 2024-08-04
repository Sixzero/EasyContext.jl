
using PromptingTools.Experimental.RAGTools: AbstractRephraser
import PromptingTools.Experimental.RAGTools: rephrase
using PromptingTools

struct JuliacodeRephraser <: AbstractRephraser end

function rephrase(rephraser::JuliacodeRephraser, question::AbstractString;
      verbose::Bool=true,
      model::String="claude", template::Symbol=:RAGRephraserByKeywords,
      cost_tracker=Threads.Atomic{Float64}(0.0), kwargs...)
  ## checks
  @show aitemplates(template)
  placeholders = only(aitemplates(template)).variables # only one template should be found
  @assert (:query in placeholders) "Provided RAG Template $(template) is not suitable. It must have a placeholder: `query`."

  msg = aigenerate(template; query = question, verbose, model, kwargs...)
  Threads.atomic_add!(cost_tracker, msg.cost)
  useful_doc_ideas, possible_files_to_edit = parse_and_evaluate_script(msg.content)
  @show length.((useful_doc_ideas, possible_files_to_edit))
  # new_questions = split(msg.content, "\n")
  return [question, useful_doc_ideas..., possible_files_to_edit...]
end

function parse_and_evaluate_script(script_content)
  # Find the start of the Julia code (after the opening ```)
  start_index = findfirst("```julia", script_content)
  if start_index !== nothing
      start_index = start_index[end] + 1
      
      # Find the end of the Julia code (before the closing ```)
      end_index = findnext("```", script_content, start_index)
      if end_index !== nothing
          end_index = end_index[1] - 1
          
          # Extract the Julia code
          julia_code = strip(script_content[start_index:end_index])
          
          # Evaluate the cleaned script in a new module to avoid polluting the global namespace
          mod = Module()
          expr = Meta.parse(string("begin\n", julia_code, "\nend"))
          @show julia_code
          Base.eval(mod, expr)
          
          # Extract the variables we're interested in
          res = Base.eval(mod, :((plan_topics, file_topics)))
          @show length(res)
          return res
          
      end
  end
  @warn "No rephrase results! $start_index"
  println("The content was:\n$script_content")
  return [], []
end
