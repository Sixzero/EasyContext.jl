using Test
using EasyContext
using EasyContext: is_ignored_by_patterns, parse_ignore_files, gitignore_to_regex, GitIgnorePattern

# Helper function to debug patterns
function debug_pattern(pattern_str, test_path, root="project")
    pattern = gitignore_to_regex(pattern_str)
    if pattern === nothing
        println("Pattern '$pattern_str' was skipped (comment or empty)")
        return false
    end
    
    result = occursin(pattern.regex, relpath(test_path, root))
    println("Pattern: '$pattern_str' → Regex: '$(pattern.regex)'")
    println("Testing path: '$test_path' → $(result ? "MATCHED" : "NOT MATCHED")")
    if pattern.is_negation
        println("Negation pattern, so file should be INCLUDED")
    else
        println("Regular pattern, so file should be IGNORED if matched")
    end
    return result
end

@testset "Gitignore Pattern Tests" begin
    # Create test patterns
    raw_patterns = [
        ".next/",         # Should match directories with content under .next/
        "node_modules/",  # Should match directories with content under node_modules/
        "*.log",          # Should match any file ending with .log
        "!important.log", # Should NOT match important.log (negation)
        ".cache/**/*",    # Should match any file under .cache/
        "build/",         # Should match directories with content under build/
        "/root_only_build/" # Should match only root_only_build/ at the root
    ]
    
    # Compile patterns
    patterns = filter(p -> p !== nothing, gitignore_to_regex.(raw_patterns))
    
    # Test directory patterns ending with slash
    @test !is_ignored_by_patterns("project/.next", patterns, "project")
    @test is_ignored_by_patterns("project/.next/file.js", patterns, "project")
    @test is_ignored_by_patterns("project/.next/ff/file.js", patterns, "project")
    @test is_ignored_by_patterns("project/.next/vendor-chunks/file.js", patterns, "project")
    @test is_ignored_by_patterns(".next/ff/file.js", patterns, ".")
    @test is_ignored_by_patterns("project/.next/subfolder/file.js", patterns, "project")
    @test is_ignored_by_patterns("project/node_modules/package.json", patterns, "project")
    
    # Test file patterns
    @test is_ignored_by_patterns("project/error.log", patterns, "project")
    @test !is_ignored_by_patterns("project/important.log", patterns, "project")
    
    # Test wildcard patterns
    @test is_ignored_by_patterns("project/.cache/subfolder/file.txt", patterns, "project")
    
    # Test that non-matching paths aren't ignored
    @test !is_ignored_by_patterns("project/src/file.js", patterns, "project")
    @test !is_ignored_by_patterns("project/.nextversion/file.js", patterns, "project")
    
    # Test leading slash behavior
    @test is_ignored_by_patterns("project/build/output.js", patterns, "project")
    @test is_ignored_by_patterns("project/src/build/output.js", patterns, "project")
    @test is_ignored_by_patterns("project/root_only_build/file.js", patterns, "project")
    @test !is_ignored_by_patterns("project/src/root_only_build/file.js", patterns, "project")
    
    # Additional edge case tests
    @testset "Complex Pattern Edge Cases" begin
        # Double asterisk patterns
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("**/file.txt")])
        @test is_ignored_by_patterns("project/any/depth/of/dirs/file.txt", complex_patterns, "project")
        @test !is_ignored_by_patterns("project/not_file.txt", complex_patterns, "project")
        
        # Nested negation patterns
        complex_patterns = filter(p -> p !== nothing, gitignore_to_regex.(["*.log", "!logs/important/*.log"]))
        @test !is_ignored_by_patterns("project/logs/important/debug.log", complex_patterns, "project")
        @test is_ignored_by_patterns("project/other/debug.log", complex_patterns, "project")
        
        # Multiple patterns applying to the same file (precedence)
        complex_patterns = filter(p -> p !== nothing, gitignore_to_regex.(["*.md", "!README.md"]))
        @test !is_ignored_by_patterns("project/README.md", complex_patterns, "project")
        
        complex_patterns = filter(p -> p !== nothing, gitignore_to_regex.(["!README.md", "*.md"]))
        @test is_ignored_by_patterns("project/README.md", complex_patterns, "project")  # Order matters!
        
        # Path segment boundaries
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("logs/")])
        @test !is_ignored_by_patterns("project/logs", complex_patterns, "project")
        @test is_ignored_by_patterns("project/logs/file.txt", complex_patterns, "project")
        @test !is_ignored_by_patterns("project/logs-extra/file.txt", complex_patterns, "project")
        
        # Complex wildcards
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("temp_*_???.tmp")])
        @test is_ignored_by_patterns("project/temp_file_123.tmp", complex_patterns, "project")
        @test !is_ignored_by_patterns("project/temp_file_1.tmp", complex_patterns, "project")
        
        # Trailing patterns with double asterisks
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("**/logs")])
        @test is_ignored_by_patterns("project/any/path/to/logs", complex_patterns, "project")
        @test !is_ignored_by_patterns("project/any/path/to/logs-dir", complex_patterns, "project")
        
        # Leading slash combined with wildcards
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("/dist/*.min.js")])
        @test is_ignored_by_patterns("project/dist/file.min.js", complex_patterns, "project")
        @test !is_ignored_by_patterns("project/nested/dist/file.min.js", complex_patterns, "project")
        
        # Edge cases with special characters
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("*.with.dots.*")])
        @test is_ignored_by_patterns("project/file.with.dots.txt", complex_patterns, "project")
        
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex("[special].txt")])
        @test is_ignored_by_patterns("project/[special].txt", complex_patterns, "project")
        
        # Root directory patterns
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex(".git/")])
        @test is_ignored_by_patterns("project/.git/config", complex_patterns, "project")
        
        complex_patterns = filter(p -> p !== nothing, [gitignore_to_regex(".git")])
        @test is_ignored_by_patterns("project/.git", complex_patterns, "project")
    end
end
