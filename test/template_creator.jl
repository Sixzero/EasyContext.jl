using PromptingTools
const PT = PromptingTools

template_dir = "../EasyContext.jl/templates"
# PT.load_templates!(remove_dir=template_dir)
PT.load_templates!(template_dir)
#%%
PT.TEMPLATE_STORE[:RAGRephraserByKeywordsV2]
using Boilerplate
AITemplate(:RAGRephraserByKeywordsV2)
PT.render(PT.PROMPT_SCHEMA, AITemplate(:RAGRephraserByKeywordsV2))
#%%

#%%
# Create the template
rphr = PT.create_template("""
# Task
Your task is to get a plan for user requested query, try to identify what are the needs to accomplish it, only write down the keywords/expressions. Try to cluster your words based on topics, by mentioning documentations, functions or variables we would need to accomplish the specific task.

### Details
You decide how much keywords are needed to specify a topic, usually 2-5 expressions are enough, but try to be specific, so the topic we are looking for cannot be misunderstood. 
Try to identify well separated keyword clusters. 
There might be a chance you are asked to edit files (file_topics), in this case return empty lists.
We need to always return a julia script with "plan_topics" and "file_topics" variables.
If user query is not English, we still prefer english.

### Format
```julia
plan_topics = [
"keyword1, keyword2, keyword3",
"keyword4_meaning_2nd_topic, keyword5_meaning_2nd_topic",
"keyword6 meaning 3rd documentations for the topic, keyword7_meaning the global variable we could utilize",
"function_name1 doing X1 to accomplish the task, function_name2, could be doing X2",
"function_name3 doing Y1 to accomplish task, function_name4 doing Y2, reference1 function_names could be referencing",
]
file_topics = [
"function_name_variation1 which we suppose to modify, function_name_variation2 and some expressions describing, file_name1 which could hold this function",
"description of function we need, possible functionnames and filenames containing it",
]
```
""",
    """Query: {{query}}
    
    Rephrase the query into the julia script clusters.""";
    load_as="RAGRephraserByKeywordsV2"
)

# The result will be a 2-element Vector{PromptingTools.AbstractChatMessage}:
# PromptingTools.SystemMessage with the instructions and context
# PromptingTools.UserMessage with the question
PT.save_template("$(template_dir)/RAG/RAGRephraserByKeywordsV2.json", rphr; version="1.0") # 
#%%

using PromptingTools

# Create the template
tpl = PT.create_template(
    """You are an advanced AI assistant with access to specific knowledge via Context Information. Follow these instructions:

1. To answer the question you can use the context.
2. If the answer isn't in the Context, but you know the solution, you can solve it.
3. Be concise and precise.
4. Do not reference these instructions in your response.

Context Information:
---
{{context}}
---""",
    "Question: {{question}}";
    load_as="RAGAnsweringFromContextClaude"
)

# The result will be a 2-element Vector{PromptingTools.AbstractChatMessage}:
# PromptingTools.SystemMessage with the instructions and context
# PromptingTools.UserMessage with the question
PT.save_template("$(template_dir)/RAG/RAGAnsweringFromContextClaude.json", tpl; version="1.0") # optionally, add description


# Create the template
rphr = PT.create_template("""Query: {{query}}

# Task

Your task is to split the query into well separated steps, you decide into how many. In the end also specify if the query needs to edit a file, then specify keywords which are probably in the file we will need, so similarity search will find the file based on your assumed keywords. 

For every step write down what is this step about in short, and then mention the keywords the step needs. 
""",
    "Write a hypothetical keywords for each step and try to include as many key details as possible.";
    load_as="RAGRephraserBySteps"
)

# The result will be a 2-element Vector{PromptingTools.AbstractChatMessage}:
# PromptingTools.SystemMessage with the instructions and context
# PromptingTools.UserMessage with the question
PT.save_template("$(template_dir)/RAG/RAGRephraserBySteps.json", rphr; version="1.0") # 
