using Test
using EasyContext
using BenchmarkTools
using EasyContext: is_project_file, ignore_file, is_ignored_by_patterns

@testset "File Filtering Performance Tests" begin
    # Test data
    project_files_vec = ["Dockerfile", "docker-compose.yml", "Makefile", "LICENSE", "package.json"]
    project_files_set = Set(project_files_vec)
    file_extensions_vec = ["jl", "py", "js", "md"]
    file_extensions_set = Set(file_extensions_vec)
    ignored_patterns = [".log", ".git", "node_modules/"]
    
    # Sample filenames
    match_files = ["Dockerfile", "example.jl", "script.py", "readme.md"]
    non_match_files = ["unknown.txt", "image.png", "data.csv"]
    ignored_files = ["error.log", ".git/config", "node_modules/package.json"]
    
    @testset "is_project_file Performance" begin
        # Test correctness
        for file in match_files
            @test is_project_file(file, project_files_set, file_extensions_set)
        end
        
        for file in non_match_files
            @test !is_project_file(file, project_files_set, file_extensions_set)
        end
        
        # Benchmark using Vector vs Set for extensions
        vec_times = @benchmark is_project_file(sample, $project_files_vec, $file_extensions_vec) evals=1000 samples=5 seconds=1 setup=(sample = rand($match_files))
        set_times = @benchmark is_project_file(sample, $project_files_set, $file_extensions_set) evals=1000 samples=5 seconds=1 setup=(sample = rand($match_files))
        
        println("Vector implementation time: ", minimum(vec_times))
        println("Set implementation time: ", minimum(set_times))
    end
    
    @testset "File extension extraction" begin
        @test EasyContext.get_file_extension("file.txt") == "txt"
        @test EasyContext.get_file_extension("path/to/file.js") == "js"
        @test EasyContext.get_file_extension("multiple.dots.md") == "md"
        @test EasyContext.get_file_extension("no_extension") == ""
        @test EasyContext.get_file_extension(".hidden") == "hidden"
    end
    
    @testset "ignore_file Test" begin
        # Test the improved ignore_file function
        for file in ignored_files
            @test ignore_file(file, ignored_patterns)
        end
        
        # Files that shouldn't be ignored
        for file in match_files
            @test !ignore_file(file, ignored_patterns)
        end
    end
end
