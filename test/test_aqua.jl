using Test
using Aqua
using EasyContext

@testset "Aqua.jl Tests" begin
    Aqua.test_all(EasyContext; 
        ambiguities=true,           # Test for type ambiguities
        unbound_args=true,          # Test for unbound type parameters
        undefined_exports=true,     # Test for undefined exports
        project_extras=true,        # Test for project extras
        stale_deps=true,           # Test for stale dependencies
        deps_compat=true,          # Test for dependencies compatibility
        piracies=true              # Test for method piracies
    )
end
