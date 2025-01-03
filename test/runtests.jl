using Test

@testset "EasyContext.jl" begin
    include("test_gmail_draft.jl")
    include("test_env_variables.jl")
    include("test_full_file_chunker.jl")
    include("test_context_planner.jl")
    include("test_executionplanner_context.jl")  # its not free. it cals out to cloud.
    include("test_CTXBetterConversation.jl")
    include("test_workspace.jl")
    include("transform/test_instant_apply.jl")
end
