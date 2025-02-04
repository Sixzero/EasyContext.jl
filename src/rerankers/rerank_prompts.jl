
# Helper function to create the RankGPT prompt
function create_rankgpt_prompt_v0(question::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
  top_n = min(top_n, length(documents))
  document_context = join(["<doc id=\"$i\">$doc</doc>" for (i, doc) in enumerate(documents)], "\n")
  prompt = """
  <question>$question</question>

  <instruction>
  $(BASIC_INSTRUCT(documents, top_n))
  If a selected document uses a function we probably need, it's preferred to include it in the ranking.
  </instruction>

  $(DOCS_FORMAT(documents))

  $OUTPUT_FORMAT
  """
  return prompt
end
# Helper function to create the RankGPT prompt
function create_rankgpt_prompt_v1(question::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
  top_n = min(top_n, length(documents))
  prompt = """
  <instruction>
  $(BASIC_INSTRUCT(documents, top_n))
  If a selected document which implements a function we probably need, it's preferred to include it in the ranking.
  </instruction>

  $(DOCS_FORMAT(documents))

  $(QUESTION_FORMAT(question))
  $OUTPUT_FORMAT
  """
  return prompt
end
# Helper function to create the RankGPT prompt
function create_rankgpt_prompt_v2(question::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
  top_n = min(top_n, length(documents))
  prompt = """
  <instruction>
  $(BASIC_INSTRUCT(documents, top_n))
  Relevant documents:
  - The most relevant are the ones which we need to edit based on the question.
  - Also relevant are the ones which hold something we need for editing, like a function.
  - Consider the context and potential usefulness of each document for answering the question.
  </instruction>

  $(DOCS_FORMAT(documents))
  
  $(QUESTION_FORMAT(question))
  
  $OUTPUT_FORMAT
  """
  return prompt
end

function create_rankgpt_prompt_v3(question::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
  top_n = min(top_n, length(documents))
  prompt = """
  <instruction>
  Rank the following documents based on their relevance to the question. 
  Provide rankings as a comma-separated list of document IDs, where the 1st is the most relevant.
  Include up to $(top_n) documents, fewer if not all are relevant.
  Only use document IDs between 1 and $(length(documents)).
  Return an empty list [] if no documents are relevant.

  Relevance Criteria:
  1. Direct Answer: Documents that directly answer or address the question.
  2. Contextual Information: Documents providing necessary background or context.
  3. Code Relevance: Documents containing functions or code snippets relevant to the question.
  4. Implementation Details: Documents with specific implementation details related to the question.
  5. Potential Modifications: Documents that might need editing based on the question.

  Ranking Process:
  - Carefully analyze each document for its relevance to the question.
  - Consider both the content and the potential usefulness of each document.
  - Prioritize documents that are most likely to contribute to a comprehensive answer.
  - If multiple documents are equally relevant, prioritize those with more specific or detailed information.
  </instruction>
  $(DOCS_FORMAT(documents))

  $(QUESTION_FORMAT(question))
  
  $OUTPUT_FORMAT
  """
  return prompt
end
# Helper function to create the RankGPT prompt
function rerank_prompt_v4(query::AbstractString, documents::Vector{<:AbstractString}, top_n::Int)
  top_n = min(top_n, length(documents))
  sys_prompt = """
  # Instructions
  Rank the following documents based on their relevance to the "User query". 
  Output the rankings as a comma-separated list of document IDs, where the 1st is the most relevant. 
  At max select the $(top_n) docs, fewer is also okay. You can return an empty list [] if nothing is relevant. 
  Only use document IDs between 1 and $(length(documents)).


  # Relevant documents are:
  $RELEVANT_DOCS_ARE
  

  # Output format:
  $OUTPUT_FORMAT_V2
  """
  user_prompt = """
  # User query:
  $query

  # Documents:
  $(DOCS_FORMAT_V2(documents))
  """
  return [SystemMessage(content=sys_prompt), UserMessage(content=user_prompt)]
end

const OUTPUT_FORMAT = """<output_format>
  [Rankings, comma-separated list of document ids]
  </output_format>"""
const OUTPUT_FORMAT_V2 = """Only the rankings. A comma-separated list of document ids."""
const RELEVANT_DOCS_ARE = """- The most relevant docs are the ones which we need to edit based on the query.
  - Also relevant are the ones which hold something we need for editing, like a function.
  - Consider the context and potential usefulness of each document for answering the query.
  """

BASIC_INSTRUCT(docs, top_n) = """
  Rank the following documents based on their relevance to the question. 
  Output only the rankings as a comma-separated list of document IDs, where the 1st is the most relevant. 
  At max select the top_$(top_n) docs, fewer is also okay. You can return an empty list [] if nothing is relevant. 
  Only use document IDs between 1 and $(length(docs))."""
QUESTION_FORMAT(question) = """<question>
$question
</question>"""
function DOCS_FORMAT(docs)
  document_context = join(("<doc id=\"$i\">\n$doc\n</doc>" for (i, doc) in enumerate(docs)), "\n")
  """<documents>
  $document_context
  </documents>
  """
end
function DOCS_FORMAT_V2(docs)
  document_context = join(("# Doc id=$i\n$doc" for (i, doc) in enumerate(docs)), "\n\n")
end
