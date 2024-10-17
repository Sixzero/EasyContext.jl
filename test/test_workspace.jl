using Test
using EasyContext
using EasyContext: Workspace, FirstAsRootResolution, LongestCommonPathResolution, resolve
using EasyContext: get_project_files

@testset "Workspace Tests" begin
    @testset "Workspace Constructor" begin
        w = Workspace(project_paths=["path1", "path2"])
        @test w.project_paths == ["path1", "path2"]
        @test isempty(w.rel_project_paths)
        @test w.root_path == ""
        @test w.resolution_method isa FirstAsRootResolution
    end

    @testset "FirstAsRootResolution" begin
        paths = ["/home/user/root", "/home/user/root/project1", "/home/user/root/project2"]
        root_path, rel_paths = resolve(FirstAsRootResolution(), paths)
        @test root_path == "/home/user/root"
        @test rel_paths == [".", "project1", "project2"]

        # Test with single path
        single_path = ["/home/user/project"]
        root_path, rel_paths = resolve(FirstAsRootResolution(), single_path)
        @test root_path == "/home/user/project"
        @test rel_paths == ["."]
        
        # Test with empty input
        empty_paths = String[]
        root_path, rel_paths = resolve(FirstAsRootResolution(), empty_paths)
        @test root_path == ""
        @test isempty(rel_paths)
    end

    @testset "LongestCommonPathResolution" begin
        paths = ["/home/user/project/src/file1.jl", "/home/user/project/test/file2.jl", "/home/user/project/docs/file3.md"]
        common_path, rel_paths = resolve(LongestCommonPathResolution(), paths)
        @test common_path == "/home/user/project"
        @test rel_paths == ["src/file1.jl", "test/file2.jl", "docs/file3.md"]

        # Test with single path
        single_path = ["/home/user/project"]
        common_path, rel_paths = resolve(LongestCommonPathResolution(), single_path)
        @test common_path == "/home/user/project"
        @test rel_paths == ["."]
        
        # Test with empty input
        empty_paths = String[]
        common_path, rel_paths = resolve(LongestCommonPathResolution(), empty_paths)
        @test common_path == ""
        @test isempty(rel_paths)
    end

    @testset "Workspace with FirstAsRootResolution" begin
        original_dir = pwd()
        temp_dir = tempname()
        try
            mkdir(temp_dir)
            proj1 = joinpath(temp_dir, "project1")
            proj2 = joinpath(temp_dir, "project2")
            mkdir(proj1)
            mkdir(proj2)
            
            w = Workspace([proj1, proj2])
            @test rstrip(w.root_path, '/') == rstrip(temp_dir * "/project1", '/')
            @test w.rel_project_paths == [".", "../project2"]
            @test w.resolution_method isa FirstAsRootResolution
        finally
            cd(original_dir)  # Change back to the original directory
            rm(temp_dir, recursive=true, force=true)
        end
    end

    @testset "Workspace with LongestCommonPathResolution" begin
        original_dir = pwd()
        temp_dir = tempname()
        try
            mkdir(temp_dir)
            proj1 = joinpath(temp_dir, "project1")
            proj2 = joinpath(temp_dir, "project2")
            mkdir(proj1)
            mkdir(proj2)
            
            w = Workspace([temp_dir, proj1, proj2], resolution_method=LongestCommonPathResolution())
            @test rstrip(w.root_path, '/') == rstrip(temp_dir, '/')
            @test w.rel_project_paths == [".", "project1", "project2"]
            @test w.resolution_method isa LongestCommonPathResolution
        finally
            cd(original_dir)  # Change back to the original directory
            rm(temp_dir, recursive=true, force=true)
        end
    end

    @testset "get_project_files" begin
        original_dir = pwd()
        temp_dir = tempname()
        try
            mkdir(temp_dir)
            # Create a more complex directory structure
            proj1 = joinpath(temp_dir, "project1")
            proj2 = joinpath(temp_dir, "project2")
            mkdir(proj1)
            mkdir(proj2)
            mkdir(joinpath(proj1, "src"))
            mkdir(joinpath(proj2, "test"))
            
            # Create some test files
            touch(joinpath(proj1, "src", "file1.jl"))
            touch(joinpath(proj1, "README.md"))
            touch(joinpath(proj2, "file2.jl"))
            touch(joinpath(proj2, "test", "test1.jl"))
            touch(joinpath(proj2, "ignored_file.log"))  # Should be ignored based on extension
            
            # Test with common path resolution
            w_common = Workspace([proj1, proj2])
            files_common = w_common()
            @test length(files_common) == 4
            @test any(f -> endswith(f, "src/file1.jl"), files_common)
            @test any(f -> endswith(f, "README.md"), files_common)
            @test any(f -> endswith(f, "file2.jl"), files_common)
            @test any(f -> endswith(f, "test/test1.jl"), files_common)
            @test !any(f -> endswith(f, "ignored_file.log"), files_common)

            # Test with root and relatives resolution
            w_root = Workspace([proj1, proj2], resolution_method=FirstAsRootResolution())
            files_root = w_root()
            
            @test length(files_root) == 4
            abs_files_root = [normpath(joinpath(w_root.root_path, f)) for f in files_root]
            @test any(f -> endswith(f, "project1/src/file1.jl"), abs_files_root)
            @test any(f -> endswith(f, "project1/README.md"), abs_files_root)
            @test any(f -> endswith(f, "project2/file2.jl"), abs_files_root)
            @test any(f -> endswith(f, "project2/test/test1.jl"), abs_files_root)
            @test !any(f -> endswith(f, "ignored_file.log"), abs_files_root)

            # Test relative paths
            rel_files_common = [normpath(joinpath(w_common.root_path, f)) for f in files_common]
            @test any(f -> endswith(f, joinpath("project1", "src", "file1.jl")), rel_files_common)
            @test any(f -> endswith(f, joinpath("project1", "README.md")), rel_files_common)
            @test any(f -> endswith(f, joinpath("project2", "file2.jl")), rel_files_common)
            @test any(f -> endswith(f, joinpath("project2", "test", "test1.jl")), rel_files_common)

            # Compare normalized paths
            @test Set(normpath.(abs_files_root)) == Set(normpath.(rel_files_common))
        finally
            cd(original_dir)  # Change back to the original directory
            rm(temp_dir, recursive=true, force=true)
        end
    end

    @testset "LongestCommonPathResolution" begin
        paths = ["/home/user/project/src/file1.jl", "/home/user/project/test/file2.jl", "/home/user/project/docs/file3.md"]
        common_path, rel_paths = resolve(LongestCommonPathResolution(), paths)
        @test common_path == "/home/user/project"
        @test rel_paths == ["src/file1.jl", "test/file2.jl", "docs/file3.md"]

        # Test with single path
        single_path = ["/home/user/project"]
        common_path, rel_paths = resolve(LongestCommonPathResolution(), single_path)
        @test common_path == "/home/user/project"
        @test rel_paths == ["."]
        
        # Test with empty input
        empty_paths = String[]
        common_path, rel_paths = resolve(LongestCommonPathResolution(), empty_paths)
        @test common_path == ""
        @test isempty(rel_paths)
    end

end
;
