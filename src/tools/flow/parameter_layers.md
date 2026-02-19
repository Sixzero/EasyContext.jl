# Tool Parameter Layers

This document defines how parameters should be sourced and owned when running tools.

## Goal

Separate execution environment concerns from tool contract data so behavior is predictable, secure, and composable.

## The 3 Layers

### 1) Runtime Globals (Context-owned)

Owned by global execution context (`ctx`).
These are not part of the LLM tool-call contract.

Examples:
- `edge_id`
- `client`
- `io`
- auth/session metadata
- permission policy flags
- cancellation/timeouts

Rules:
- LLM must not set these.
- They are injected by the runtime.
- All tools should read these via context when needed.

### 2) Tool Configuration (Generator-owned)

Owned by tool generator / tool construction.
These are fixed for the tool instance unless explicitly marked overridable.

Examples:
- `root_path`
- `model`
- allowed sub-tools
- static mode flags

Rules:
- Set via `ToolGenerator(..., args...)` or equivalent creation path.
- Not directly user-editable through the tool schema unless intentionally exposed.

### 3) Invocation Arguments (LLM-owned)

Owned by the actual tool call payload (schema params).
These are the per-call inputs requested by the model.

Examples:
- `path`
- `url`
- `query`
- `prompt`
- `content`

Rules:
- Must be schema-validated and type-coerced.
- Should represent domain intent, not runtime control.

## Precedence and Override Policy

Default precedence (for fields that are allowed to overlap):
1. Invocation arguments (Layer 3)
2. Tool configuration (Layer 2)
3. Runtime defaults (Layer 1)

But only for explicitly overridable fields.

Non-overridable fields must remain context-owned:
- `edge_id`
- `client`
- `io`
- permission/capability controls

## Recommended Ownership Split

Tool-owned fields:
- domain and scope fields (for example `root_path`, `path`, `query`, `content`)

Context-owned fields:
- execution environment and cross-cutting runtime concerns

## Implementation Notes

- Resolve effective values once during tool creation.
- Keep runtime context immutable during a single tool execution.
- Avoid storing context-owned values as tool fields unless there is a strong reason.
- For backward compatibility during migrations, accept old parameter names (for example `file_path`) and normalize to new names (for example `path`).
