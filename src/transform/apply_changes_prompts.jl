using PromptingTools: create_template


function get_merge_prompt_v1(original_content, changes_content)
  """You are an AI assistant specialized in merging code changes. You will be provided with the <original content> and a <changes content> to be applied. Your task is to generate the final content after applying the <changes content>. 
  Here's what you need to do:

  1. Analyze the <original content> and the <changes content>.
  2. Apply the changes specified in the <changes content> to the <original content>.
  3. Ensure that the resulting code is syntactically correct and maintains the original structure where possible.
  4. If there are any conflicts or ambiguities, resolve them in the most logical way.
  5. Return only the final merged content, between <final> and </final> tags.

  <original content>
  $original_content
  </original content>

  <changes content>
  $changes_content
  </changes content>

  Please provide the final merged content between <final> and </final>.
  """
end

function get_merge_prompt_v2(original_content, changes_content)
  """You are a code merge specialist. Merge the <ORIGINAL> code with the <CHANGES> following these rules:

  1. Apply all modifications from <CHANGES> to <ORIGINAL>
  2. Keep original formatting (spaces/tabs)
  3. If <CHANGES> contains '// ... existing code ...' preserve that part from <ORIGINAL>
  4. Keep imports and using statements intact unless explicitly modified
  5. Return only the final code between <final> and </final> tags

  <ORIGINAL>
  $original_content
  </ORIGINAL>

  <CHANGES>
  $changes_content
  </CHANGES>

  Provide merged code between <final> and </final>.
  """
end
