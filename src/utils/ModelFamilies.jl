export family_model, set_model_families!, review_default_model

# Current model per family: the single source is packages/shared-fbe/src/model_families.json
# (the host fills this via `set_model_families!`; TODO4AI loads it at startup and from the
# backend). These defaults only cover a standalone EasyContext. Never pin a version at a call
# site: ask for the family, so a bump of `current` moves every sub-agent and helper with it.
const MODEL_FAMILY_CURRENT = Dict{String,String}(
    "claude-opus"   => "anthropic:anthropic/claude-opus-5.5",
    "claude-sonnet" => "anthropic:anthropic/claude-sonnet-5.5",
    "claude-haiku"  => "anthropic:anthropic/claude-haiku-5.5",
    "gpt-astra"     => "openai:openai/gpt-6.2-astra",
    "gpt-sol"       => "openai:openai/gpt-6.2-sol",
    "gpt-luna"      => "openai:openai/gpt-6-luna",
)
const MODEL_FAMILY_LOCK = ReentrantLock()

"""`provider:author/model` of the family's current version (KeyError for an unknown family)."""
family_model(family::AbstractString) = lock(() -> MODEL_FAMILY_CURRENT[family], MODEL_FAMILY_LOCK)

"""Merge `family => qualified id` pairs (from model_families.json) into the registry."""
set_model_families!(pairs) = lock(MODEL_FAMILY_LOCK) do
    for (k, v) in pairs; MODEL_FAMILY_CURRENT[String(k)] = String(v); end
end

# Review runs on another vendor than the parent (a model shouldn't review itself):
# Anthropic/Claude parent → current Astra, anything else (or unknown) → current Opus.
review_default_model(parent_model) =
    occursin(r"anthropic|claude", lowercase(string(something(parent_model, "")))) ?
        family_model("gpt-astra") : family_model("claude-opus")
