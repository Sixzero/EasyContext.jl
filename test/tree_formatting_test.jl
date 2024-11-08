using Test
using EasyContext: Workspace

@testset "Tree Formatting" begin
    # Create a temporary directory structure
    mktempdir() do root
        # Create test directory structure
        mkpath(joinpath(root, "dir1/subdir1"))
        mkpath(joinpath(root, "dir1/subdir2"))
        mkpath(joinpath(root, "dir2/transform"))  # Added transform directory
        
        # Create some test files
        touch(joinpath(root, "dir1/subdir1/file1.jl"))
        touch(joinpath(root, "dir1/subdir2/file2.jl"))
        touch(joinpath(root, "dir2/file3.jl"))
        touch(joinpath(root, "dir2/transform/test1.jl"))  # Added file in transform directory
        touch(joinpath(root, "dir2/transform/test2.jl"))  # Added another file
        
        # Create workspace
        w = Workspace([root])
        
        # Capture the output
        output = String[]
        redirect_stdout(IOBuffer()) do
            print_project_tree(w, ".")
        end |> buf -> (output = split(String(take!(buf)), '\n'))
        
        # Test the formatting
        expected_pattern = [
            r"Project structure:",
            r"├── dir1/",
            r"│   ├── subdir1/",
            r"│   │   └── file1\.jl",
            r"│   └── subdir2/",
            r"│       └── file2\.jl",
            r"└── dir2/",
            r"    ├── file3\.jl",
            r"    └── transform/",
            r"        ├── test1\.jl",
            r"        └── test2\.jl"
        ]
        
        for (i, pattern) in enumerate(expected_pattern)
            @test occursin(pattern, output[i]) "Line $i doesn't match pattern: $pattern\nGot: $(output[i])"
        end
    end
end
