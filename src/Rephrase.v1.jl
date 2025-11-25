
using RAGTools: AbstractRephraser
import RAGTools: rephrase

Base.@kwdef struct JuliacodeRephraser <: AbstractRephraser
  template::Symbol=:RAGRephraserByKeywords
  model::String="claude"
  verbose::Bool=true
end

function rephrase(rephraser::JuliacodeRephraser, question::AbstractString;
      cost_tracker=Threads.Atomic{Float64}(0.0), kwargs...)
  ## checks
  model, template, verbose = rephraser.model, rephraser.template, rephraser.verbose
  placeholders = only(aitemplates(template)).variables # only one template should be found
  @assert (:query in placeholders) "Provided RAG Template $(template) is not suitable. It must have a placeholder: `query`."

  msg = aigen(template, model; query = question, verbose, kwargs...)
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
          
          # Escape unescaped $ symbols
          escaped_code = replace(julia_code, r"(?<!\\)\$" => raw"\$")

          mod = Module()
          expr = Meta.parse(string("begin\n", escaped_code, "\nend"))
          Base.eval(mod, expr)
          
          # Extract the variables we're interested in
          res = Base.eval(mod, :((plan_topics, file_topics)))
          return res
          
      end
  end
  @warn "No rephrase results! $start_index"
  println("The content was:\n$script_content")
  return [], []
end
