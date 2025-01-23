
using Test
using DataStructures
import EasyContext
using EasyContext: Context
using EasyContext: ChangeTracker, get_chunk_standard_format
using Random

# TODO default_source_parser is updated to reparse_chunk
@testset "ChangeTracker tests" begin
    @testset "Basic functionality" begin
        # Custom source parser for testing
        function test_source_parser(source::String, current_content::String)
            if source == "file1.txt"
                return get_chunk_standard_format(source, "updated_content1")
            elseif source == "file3.txt"
                return get_chunk_standard_format(source, "content3")
            else
                # For any other file, including file2.txt, return the current content
                return current_content
            end
        end

        tracker = ChangeTracker(source_parser=test_source_parser)
        src_content = OrderedDict{String,String}(
            "file1.txt" => get_chunk_standard_format("file1.txt", "content1"),
            "file2.txt" => get_chunk_standard_format("file2.txt", "content2")
        )
        updated_tracker, updated_content = tracker(src_content)

        @test length(updated_tracker.changes) == 2
        @test updated_tracker.changes["file1.txt"] == :NEW
        @test updated_tracker.changes["file2.txt"] == :NEW
        @test updated_content == src_content

        # Second call with changes
        new_src_content = OrderedDict{String,String}(
            "file1.txt" => get_chunk_standard_format("file1.txt", "content1"),
            "file2.txt" => get_chunk_standard_format("file2.txt", "content2"),
            "file3.txt" => get_chunk_standard_format("file3.txt", "content3")
        )

        updated_tracker, updated_content = tracker(new_src_content)
        @test length(updated_tracker.changes) == 3
        @test updated_tracker.changes["file1.txt"] == :UPDATED
        @test updated_tracker.changes["file2.txt"] == :UNCHANGED
        @test updated_tracker.changes["file3.txt"] == :NEW
        @test updated_content == new_src_content
    end

    @testset "Multiple updates" begin
        content_store = Dict{String, String}(
            "./src/contexts/ContextNode.jl" => "# Content of ContextNode.jl"
        )
        
        function test_source_parser(source::String, current_content::String)
            return get_chunk_standard_format(source, get(content_store, source, current_content))
        end

        tracker = ChangeTracker(source_parser=test_source_parser)
        sources = ["./src/contexts/ContextNode.jl"]
        
        # First update
        src_content = OrderedDict(sources[1] => get_chunk_standard_format(sources[1], content_store[sources[1]]))
        updated_tracker, _ = tracker(src_content)
        
        @test length(updated_tracker.changes) == 1
        @test updated_tracker.changes[sources[1]] == :NEW

        # Second update (no change)
        updated_tracker, _ = tracker(src_content)
        
        @test length(updated_tracker.changes) == 1
        @test updated_tracker.changes[sources[1]] == :UNCHANGED

        # Third update (with change)
        content_store[sources[1]] = "# Updated content of ContextNode.jl"
        updated_tracker, _ = tracker(src_content)
        
        @test length(updated_tracker.changes) == 1
        @test updated_tracker.changes[sources[1]] == :UPDATED

        # Fourth update (remove a file)
        empty_content = OrderedDict{String,String}()
        updated_tracker, _ = tracker(empty_content)
        
        @test isempty(updated_tracker.changes)
    end

    @testset "Default source parser with temporary file" begin
        function append_content!(file_path::String, content::String)
            open(file_path, "a") do io
                write(io, content)
            end
        end
        # Create a temporary file
        temp_dir = mktempdir()
        temp_file = joinpath(temp_dir, "test_file.txt")
        
        # Write initial content
        write(temp_file, "Initial content")

        tracker = ChangeTracker()  # Using default source parser
        
        # First run
        src_content = OrderedDict{String,String}(
            temp_file => default_source_parser(temp_file, "")
        )
        updated_tracker, updated_content = tracker(src_content)

        @test length(updated_tracker.changes) == 1
        @test updated_tracker.changes[temp_file] == :NEW
        @test updated_content == src_content

        # Modify the file
        append_content!(temp_file, "\nAdditional content")

        # Second run
        src_content = Context(OrderedDict{String,String}(
            temp_file => default_source_parser(temp_file, "")
        ))
        updated_tracker, updated_content = tracker(src_content)

        @test length(updated_tracker.changes) == 1
        @test updated_tracker.changes[temp_file] == :UPDATED
        @test updated_content == src_content

        # Third run without changes
        updated_tracker, updated_content = tracker(src_content)

        @test length(updated_tracker.changes) == 1
        @test updated_tracker.changes[temp_file] == :UNCHANGED
        @test updated_content == src_content

        # Clean up
        rm(temp_dir, recursive=true)
    end

    @testset "File deletion" begin
        function test_source_parser(source::String, current_content::String)
            if source == "file1.txt"
                return get_chunk_standard_format(source, "content1")
            elseif source == "file2.txt"
                return get_chunk_standard_format(source, "content2")
            else
                return current_content
            end
        end

        tracker = ChangeTracker(source_parser=test_source_parser)
        
        # Initial content
        src_content = OrderedDict{String,String}(
            "file1.txt" => get_chunk_standard_format("file1.txt", "content1"),
            "file2.txt" => get_chunk_standard_format("file2.txt", "content2")
        )
        updated_tracker, _ = tracker(src_content)

        @test length(updated_tracker.changes) == 2
        @test updated_tracker.changes["file1.txt"] == :NEW
        @test updated_tracker.changes["file2.txt"] == :NEW

        # Simulate file deletion by removing file2.txt
        deleted_src_content = OrderedDict{String,String}(
            "file1.txt" => get_chunk_standard_format("file1.txt", "content1")
        )
        updated_tracker, updated_content = tracker(deleted_src_content)

        @test length(updated_tracker.changes) == 1
        @test haskey(updated_tracker.changes, "file1.txt")
        @test !haskey(updated_tracker.changes, "file2.txt")
        @test updated_tracker.changes["file1.txt"] == :UNCHANGED
        @test updated_content == deleted_src_content
    end

    @testset "File content change detection" begin
        mktempdir() do temp_dir
            test_file = joinpath(temp_dir, "test_file.txt")
            write(test_file, "Initial content")

            function test_source_parser(source::String, current_content::String)
                # This parser always reads from the file, ignoring current_content
                return get_chunk_standard_format(source, read(source, String))
            end

            tracker = ChangeTracker(source_parser=test_source_parser)
            
            # Initial content
            src_content = OrderedDict{String,String}(
                test_file => get_chunk_standard_format(test_file, "Initial content")
            )
            updated_tracker, _ = tracker(src_content)

            @test length(updated_tracker.changes) == 1
            @test updated_tracker.changes[test_file] == :NEW

            # Append content to the file without changing src_content
            open(test_file, "a") do io
                write(io, "\nAdditional content")
            end

            # Use the same src_content, but the parser should detect the change
            updated_tracker, updated_content = tracker(src_content)

            @test length(updated_tracker.changes) == 1
            @test updated_tracker.changes[test_file] == :UPDATED
            @test occursin("Additional content", updated_content[test_file])
        end
    end
end

;
