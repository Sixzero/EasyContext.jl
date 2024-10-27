using Test

@testset "EasyContext.jl" begin
    include("test_gmail_draft.jl")
    include("test_env_variables.jl")
    # Add other test files here as needed
end
