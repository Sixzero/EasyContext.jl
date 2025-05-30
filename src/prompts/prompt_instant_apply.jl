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
  """You are a code merge specialist. Merge the <ORIGINAL> code with the changes inside <PATCH> tags. 
  
  # Follow these rules:
  1. Apply ALL modifications from <PATCH> to <ORIGINAL>.
  2. If <PATCH> contains '... existing code ...' preserve that part from <ORIGINAL>.
  3. <PATCH> might indicate line deletions. In that case remove those lines from <final> result.
  4. <PATCH> might contain instructions. In that case follow them.
  5. <PATCH> might contain non-code parts in the end after  "```" keep that part as is.
  6. Keep original formatting (spaces/tabs)
  7. Return only the final code between <FINAL> tags with ALL the changes applied.
  8. If <PATCH> contains a complete file replacement (full file content), return exactly: <COMPLETE_REPLACEMENT/>

  <ORIGINAL>
  $original_content
  </ORIGINAL>

  <PATCH>
  $changes_content
  </PATCH>

  Provide merged code between <FINAL> and </FINAL>, or <COMPLETE_REPLACEMENT/> if patch contains full file.
  """
end

function get_patch_merge_prompt(original_content, changes_content)
  """You are a code merge specialist. Merge the <ORIGINAL> code with the <PATCH> following these rules:

  1. Apply all modifications from <PATCH> to <ORIGINAL>
  2. Keep original formatting (spaces/tabs)
  3. Keep imports and using statements intact unless explicitly modified
  4. Return only the final code between <final> and </final> tags

  In the end result all the + symbol listed things in the patch should be represented in some way in the <final> result.

  <ORIGINAL>
  $original_content
  </ORIGINAL>

  <PATCH>
  $changes_content
  </PATCH>

  Provide merged code between <final> and </final>.
  """
end

function get_replace_prompt(original_content, changes_content)
  """You are a pattern matching specialist. Generate a list of search and replace pairs that will transform the <ORIGINAL> content to reflect what we write in <MODIFY> tags.
  
  # Important Guidelines:

  1. Each pattern should be unique enough to match exactly what needs to be changed in <ORIGINAL> even if we need to remove something from <ORIGINAL>
  2. Include enough context in patterns to ensure correct placement
  3. Use complete code blocks when possible
  4. If changes don't specify location add the changes at the most appropriate place
  5. Only include necessary changes, but include contain all the changes we need to change
  7. Do not escape any characters - provide the exact text to match and replace

  Provide your response as MATCH/REPLACE tag pairs wrapped in <REPLACEMENTS> tag.

  # Example:

  <REPLACEMENTS>
  <MATCH>
  function to_find(exact::Code)
      # with enough context
  </MATCH>
  <REPLACE>
  function replaced_with(new::Code)
      # new implementation
  </REPLACE>
  <MATCH>pattern2</MATCH>
  <REPLACE>replacement2</REPLACE>
  </REPLACEMENTS>

  # Task

  <ORIGINAL>
  $original_content
  </ORIGINAL>
  
  <MODIFY>
  $changes_content
  </MODIFY>
  """
end

