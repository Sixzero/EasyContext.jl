
abstract type Workflow end


@kwdef mutable struct PersistableWorkFlowSettings
    version::VersionNumber = v"1.0.0"
    workflow

    timestamp::DateTime = now(UTC)
    conv_ctx::Session
    question_acc::QuestionCTX # TODO Question CTX to conv_ctx. so... with a function to get the question_acc actually.x
    julia_ctx::JuliaCTX
    workspace_ctx::WorkspaceCTX
    version_control::Union{GitTracker,Nothing}
    # workspace_paths::Vector{String}
    # ignore...
    git_paths::Vector{String}

    
    logdir::String
    config::Dict{String,Any} = Dict{String,Any}(
        "detached_git_dev" => false,  # Renamed here
        # resume=args["resume"], 
        "silent" => false,
        "loop" => false,
        "show_tokens" => false,
        "no_confirm" => false,
        "compression" => true,
        "checksum" => true
    )
end


(t::Workflow)(resume::PersistableWorkFlowSettings) = begin
    typeof(t)(resume.conv_ctx; resume.persist, resume.question_acc, 
                resume.workspace_ctx, resume.julia_ctx,
                resume.age_tracker,  
                resume.version_control,
                no_confirm=resume.config["no_confirm"], )
end



# f <- c (load state + other clients interactions)
# f -> c (user interaction + ai interaction)
# f -> b (user_interaction)
# f <- b (ai_interaction)

