using Test
@testset "EasyContext.jl" begin
    include("test_full_file_chunker.jl")
    include("test_CodeBlockExtractor.jl")
    include("test_context_planner.jl")

    include("test_CTXBetterConversation.jl")
    include("test_workspace.jl")
end

