export summarize_conversation, format_messages_for_summary

using PromptingTools

const CONVERSATION_SUMMARY_PROMPT = """This session is being continued from a previous conversation that ran out of context. The summary below covers the earlier portion of the conversation.

Create a summary with two sections:

## Analysis
Write a chronological narrative of what happened in the conversation. Walk through the key events in order - what the user asked, what was tried, what worked or didn't, and how the conversation evolved. This helps understand the context and reasoning behind decisions.

## Summary
Organize the key information into these categories:

1. **Primary Request and Intent**
   - What is the user trying to accomplish overall?
   - What specific outcomes are they looking for?

2. **Key Technical Concepts**
   - Technologies, libraries, patterns discussed
   - Important domain knowledge established

3. **Files and Code Sections**
   - List files that were created or modified
   - Include relevant code snippets that would be needed to continue the work
   - Note specific line numbers or function names when relevant

4. **Errors and Fixes**
   - What problems were encountered?
   - How were they resolved?

5. **Problem Solving**
   - Key decisions made and their rationale
   - Alternative approaches that were considered or rejected

6. **All User Messages**
   - Include the user's messages, preserving their wording to maintain intent and tone

7. **Pending Tasks**
   - What was mentioned but not yet completed?

8. **Current Work**
   - What was the conversation focused on when it ended?
   - What was the user's last question or request?

9. **Optional Next Step**
   - What would logically come next based on the conversation flow?

Be specific with file paths, function names, and error messages. Include actual code snippets when they're essential for continuing the work.

Conversation to summarize:
"""

"""
    format_messages_for_summary(messages::Vector{<:MSG}) -> String

Format messages into a simple string for summarization.
"""
function format_messages_for_summary(messages::Vector{<:MSG})
    parts = String[]
    for msg in messages
        role = msg.role == :user ? "User" : "Assistant"
        # Truncate very long messages but keep more context for code preservation
        # Use first()/last() for safe UTF-8 character-based truncation (not byte-based)
        content = if length(msg.content) > 6000
            first(msg.content, 3000) * "\n...[truncated]...\n" * last(msg.content, 2500)
        else
            msg.content
        end
        push!(parts, "[$role]\n$content")
    end
    join(parts, "\n\n---\n\n")
end

"""
    summarize_conversation(messages::Vector{<:MSG}; model="claudeh", previous_summary="") -> String

Generate a summary of conversation messages that preserves direction and key context.
"""
function summarize_conversation(messages::Vector{<:MSG}; model="claudeh", previous_summary="")
    isempty(messages) && return previous_summary

    prompt = CONVERSATION_SUMMARY_PROMPT * format_messages_for_summary(messages)

    if !isempty(previous_summary)
        prompt = """There is also a summary from even earlier in the conversation:

<earlier_summary>
$previous_summary
</earlier_summary>

Merge this earlier summary with the new conversation below. The merged summary should:
- Preserve the chronological flow from the earlier summary and continue it with new events
- Update any information that has changed (completed tasks, resolved errors, etc.)
- Keep user messages from both periods
- Remove information that is no longer relevant

""" * prompt
    end

    try
        result = PromptingTools.aigenerate(prompt; model, verbose=false)
        return strip(String(result.content))
    catch e
        @warn "Conversation summarization failed" exception=e
        # Return previous summary if we had one, at least preserve that
        return previous_summary
    end
end

