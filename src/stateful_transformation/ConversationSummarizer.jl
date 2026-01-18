export summarize_conversation, format_messages_for_summary

using PromptingTools

const CONVERSATION_SUMMARY_PROMPT = """You are summarizing a conversation that will be partially truncated. Your summary will be the ONLY memory of what happened before.

Your job: Extract what the assistant MUST remember to continue helping effectively.

Capture these (if present):
1. **DIRECTION**: What is the user trying to achieve? What's the end goal?
2. **APPROACH**: What technical approach/architecture was chosen and WHY?
3. **PROGRESS**: What was actually done? Files created/modified, functions implemented, etc.
4. **CONSTRAINTS**: User preferences, requirements, limitations mentioned ("don't use X", "must support Y")
5. **DEAD ENDS**: What was tried and DIDN'T work? (so we don't repeat mistakes)
6. **PENDING**: What was mentioned but not yet done?

Format as a dense but clear summary. Use bullet points. Be specific with file names, function names, error messages.

Example good summary:
- Goal: Implement auth system with JWT tokens
- Chose Redis for session store (faster than Postgres for this use case)
- Created src/auth/jwt.jl with generate_token/validate_token functions
- User wants explicit error messages, not generic "auth failed"
- FAILED: bcrypt was too slow, switched to argon2
- TODO: refresh token logic not yet implemented

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
        # Truncate very long messages to keep summary request manageable
        content = if length(msg.content) > 3000
            msg.content[1:1500] * "\n...[truncated]...\n" * msg.content[end-1500:end]
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
        prompt = """There is also a summary from even earlier in the conversation that should be incorporated:

<earlier_summary>
$previous_summary
</earlier_summary>

Merge the earlier summary with the new information below. Keep what's still relevant, update what changed.

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

