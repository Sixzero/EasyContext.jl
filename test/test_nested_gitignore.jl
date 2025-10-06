using Test
using EasyContext
using EasyContext: get_accumulated_ignore_patterns, is_ignored_by_patterns, gitignore_to_regex, GitIgnoreCache

@testset "Nested Gitignore Tests" begin
    # Create a temporary directory structure for testing
    mktempdir() do root_dir
        # Create nested directories
        nested_dir = joinpath(root_dir, "nested")
        deep_nested_dir = joinpath(nested_dir, "deep")
        mkpath(deep_nested_dir)
        
        # Create .gitignore files at different levels
        write(joinpath(root_dir, ".gitignore"), "*.log\n!important.log")
        write(joinpath(nested_dir, ".gitignore"), "*.txt\n!README.txt")
        write(joinpath(deep_nested_dir, ".gitignore"), "*.md\n!README.md")
        
        # Create test files
        touch(joinpath(root_dir, "test.log"))
        touch(joinpath(root_dir, "important.log"))
        touch(joinpath(nested_dir, "test.txt"))
        touch(joinpath(nested_dir, "README.txt"))
        touch(joinpath(deep_nested_dir, "test.md"))
        touch(joinpath(deep_nested_dir, "README.md"))
        
        # Create a cache
        cache = GitIgnoreCache()
        
        # Test accumulated patterns
        patterns = get_accumulated_ignore_patterns(deep_nested_dir, root_dir, [".gitignore"], cache)
        
        # Test that patterns from all levels are applied
        # Root level patterns
        @test is_ignored_by_patterns(joinpath(deep_nested_dir, "test.log"), patterns, root_dir)
        @test !is_ignored_by_patterns(joinpath(deep_nested_dir, "important.log"), patterns, root_dir)
        
        # Nested level patterns
        @test is_ignored_by_patterns(joinpath(deep_nested_dir, "test.txt"), patterns, root_dir)
        @test !is_ignored_by_patterns(joinpath(deep_nested_dir, "README.txt"), patterns, root_dir)
        
        # Deep nested level patterns
        @test is_ignored_by_patterns(joinpath(deep_nested_dir, "test.md"), patterns, root_dir)
        @test !is_ignored_by_patterns(joinpath(deep_nested_dir, "README.md"), patterns, root_dir)
        
        # Test caching - verify the cache has entries
        @test haskey(cache.patterns_by_dir, root_dir)
        @test haskey(cache.patterns_by_dir, nested_dir)
        @test haskey(cache.patterns_by_dir, deep_nested_dir)
        
        # Test that calling again uses the cache
        # We'll modify the gitignore file but not reload it
        write(joinpath(root_dir, ".gitignore"), "*.log\n*.txt\n*.md")  # Change patterns
        
        # Get patterns again - should use cached version
        cached_patterns = get_accumulated_ignore_patterns(deep_nested_dir, root_dir, [".gitignore"], cache)
        
        # Should still follow the old patterns since we're using the cache
        @test !is_ignored_by_patterns(joinpath(deep_nested_dir, "README.md"), cached_patterns, root_dir)
        
        # Create a new cache to test with fresh patterns
        new_cache = GitIgnoreCache()
        fresh_patterns = get_accumulated_ignore_patterns(deep_nested_dir, root_dir, [".gitignore"], new_cache)
        
        # With fresh patterns, README.md should now be ignored (no negation in new gitignore)
        @test is_ignored_by_patterns(joinpath(deep_nested_dir, "README.md"), fresh_patterns, root_dir)
    end
end