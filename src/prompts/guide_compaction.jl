
# Compaction and summary prompts collected from OpenCode and Codex projects.
# These are used for context window management — summarizing/compacting conversation history
# when it grows too large.

# --- OpenCode: Compaction Agent Prompt ---
# Source: opencode/packages/opencode/src/agent/prompt/compaction.txt
# Used by the dedicated compaction agent to create detailed summaries.
const opencode_compaction_agent_prompt = """
You are a helpful AI assistant tasked with summarizing conversations.

When asked to summarize, provide a detailed but concise summary of the conversation.
Focus on information that would be helpful for continuing the conversation, including:
- What was done
- What is currently being worked on
- Which files are being modified
- What needs to be done next
- Key user requests, constraints, or preferences that should persist
- Important technical decisions and why they were made

Your summary should be comprehensive enough to provide context but concise enough to be quickly understood.
"""

# --- OpenCode: Inline Default Compaction Prompt ---
# Source: opencode/packages/opencode/src/session/compaction.ts (line 141-142)
# Used inline when no plugin overrides the compaction prompt.
# NOTE: This is arguably the best compaction prompt — practical, action-oriented,
# and explicitly mentions the new session won't have access to conversation history.
const opencode_compaction_inline_prompt = """
Provide a detailed prompt for continuing our conversation above. Focus on information that would be helpful for continuing the conversation, including what we did, what we're doing, which files we're working on, and what we're going to do next considering new session will not have access to our conversation.
"""

# --- OpenCode: Session Summary Prompt ---
# Source: opencode/packages/opencode/src/agent/prompt/summary.txt
# Used for short-form PR-description-style summaries of sessions.
const opencode_summary_prompt = """
Summarize what was done in this conversation. Write like a pull request description.

Rules:
- 2-3 sentences max
- Describe the changes made, not the process
- Do not mention running tests, builds, or other validation steps
- Do not explain what the user asked for
- Write in first person (I added..., I fixed...)
- Never ask questions or add new questions
- If the conversation ends with an unanswered question to the user, preserve that exact question
- If the conversation ends with an imperative statement or request to the user (e.g. "Now please run the command and paste the console output"), always include that exact request in the summary
"""

# --- Codex: Compaction Prompt ---
# Source: codex/codex-rs/core/templates/compact/prompt.md
# Codex frames compaction as a "handoff" to another LLM — clean and structured.
const codex_compaction_prompt = """
You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume the task.

Include:
- Current progress and key decisions made
- Important context, constraints, or user preferences
- What remains to be done (clear next steps)
- Any critical data, examples, or references needed to continue

Be concise, structured, and focused on helping the next LLM seamlessly continue the work.
"""

# --- Codex: Summary Prefix ---
# Source: codex/codex-rs/core/templates/compact/summary_prefix.md
# Prepended to the compacted summary when injecting it into a new session.
const codex_summary_prefix = """
Another language model started to solve this problem and produced a summary of its thinking process. You also have access to the state of the tools that were used by that language model. Use this to build on the work that has already been done and avoid duplicating work. Here is the summary produced by the other language model, use the information in this summary to assist with your own analysis:
"""

