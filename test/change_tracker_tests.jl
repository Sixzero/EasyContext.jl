
using Test
using DataStructures
import EasyContext
using EasyContext: Context, AbstractChunk, NewlineChunker, get_chunks
using EasyContext: ChangeTracker, FileChunk, SourcePath, update_changes!
using Random
using FilePathsBase


@kwdef struct DummyChunk <: AbstractChunk
    source::String
    content::AbstractString=""
end
EasyContext.need_source_reparse(chunk::DummyChunk) = true
EasyContext.reparse_chunk(chunk::DummyChunk) = DummyChunk(chunk.source, chunk.content) # Returns the same chunk
Base.:(==)(a::DummyChunk, b::DummyChunk) = a.source == b.source && strip(a.content) == strip(b.content)

@testset failfast=true "ChangeTracker tests" begin
    @testset "Basic functionality" begin
        # Create a tracker
        tracker = ChangeTracker{DummyChunk}()
        
        # Create initial content
        src_content = OrderedDict{String, DummyChunk}(
            "file1.txt" => DummyChunk(source="file1.txt", content="content1"),
            "file2.txt" => DummyChunk(source="file2.txt", content="content2")
        )
        
        # First update - should mark all as NEW
        updated_content = update_changes!(tracker, src_content)

        @test length(tracker.changes) == 2
        @test tracker.changes["file1.txt"] == :NEW
        @test tracker.changes["file2.txt"] == :NEW
        @test updated_content == src_content

        # Manually modify the content to simulate what source_parser would do
        # This simulates the behavior of the custom source_parser in the original test
        src_content["file1.txt"] = DummyChunk(source="file1.txt", content="updated_content1")
        src_content["file3.txt"] = DummyChunk(source="file3.txt", content="content3")
        
        # Second update - should detect changes and new file
        updated_content = update_changes!(tracker, src_content)
        
        @test length(tracker.changes) == 3
        @test tracker.changes["file1.txt"] == :UPDATED
        @test tracker.changes["file2.txt"] == :UNCHANGED
        @test tracker.changes["file3.txt"] == :NEW
        @test updated_content == src_content
    end

    @testset "Multiple updates" begin
        # Create a tracker
        tracker = ChangeTracker{DummyChunk}()
        
        # Define source path
        source = "./src/contexts/ContextNode.jl"
        
        # First update with initial content
        src_content = OrderedDict(source => DummyChunk(source=source, content="# Content of ContextNode.jl"))
        _ = update_changes!(tracker, src_content)
        
        @test length(tracker.changes) == 1
        @test tracker.changes[source] == :NEW

        # Second update (no change)
        _ = update_changes!(tracker, src_content)
        
        @test length(tracker.changes) == 1
        @test tracker.changes[source] == :UNCHANGED

        # Third update (with change)
        src_content[source] = DummyChunk(source=source, content="# Updated content of ContextNode.jl")
        _ = update_changes!(tracker, src_content)
        
        @test length(tracker.changes) == 1
        @test tracker.changes[source] == :UPDATED

        # Fourth update (remove a file)
        empty_content = OrderedDict{String,DummyChunk}()
        _ = update_changes!(tracker, empty_content)
        
        @test isempty(tracker.changes)
    end

    @testset "File deletion" begin
        # Create a tracker
        tracker = ChangeTracker{DummyChunk}()
        
        # Initial content
        src_content = OrderedDict{String,DummyChunk}(
            "file1.txt" => DummyChunk(source="file1.txt", content="content1"),
            "file2.txt" => DummyChunk(source="file2.txt", content="content2")
        )
        _ = update_changes!(tracker, src_content)

        @test length(tracker.changes) == 2
        @test tracker.changes["file1.txt"] == :NEW
        @test tracker.changes["file2.txt"] == :NEW

        # Simulate file deletion by removing file2.txt
        deleted_src_content = OrderedDict{String,DummyChunk}(
            "file1.txt" => DummyChunk(source="file1.txt", content="content1")
        )
        updated_content = update_changes!(tracker, deleted_src_content)

        @test length(tracker.changes) == 1
        @test haskey(tracker.changes, "file1.txt")
        @test !haskey(tracker.changes, "file2.txt")
        @test tracker.changes["file1.txt"] == :UNCHANGED
        @test updated_content == deleted_src_content
    end

    @testset "Real file updates with NewlineChunker" begin
        # Create a temporary directory with test files
        temp_dir = mktempdir()
        
        # Create test files
        file1_path = joinpath(temp_dir, "test1.txt")
        file2_path = joinpath(temp_dir, "test2.txt")
        
        write(file1_path, "Initial content for file 1")
        write(file2_path, "Initial content for file 2")
        
        # Create a tracker
        tracker = ChangeTracker{FileChunk}()
        
        # Get chunks using NewlineChunker
        chunker = NewlineChunker{FileChunk}()
        file_paths = [Path(file1_path), Path(file2_path)]
        chunks = get_chunks(chunker, file_paths)
        
        # Convert chunks to OrderedDict for the tracker
        chunks_dict = OrderedDict{String, FileChunk}()
        for chunk in chunks
            chunks_dict[string(chunk.source.path)] = chunk
        end
        
        # First update - should mark all as NEW
        updated_content = update_changes!(tracker, chunks_dict)
        
        @test length(tracker.changes) == 2
        @test all(status -> status == :NEW, values(tracker.changes))
        
        # Second update with no changes
        chunks = get_chunks(chunker, file_paths)
        chunks_dict = OrderedDict{String, FileChunk}()
        for chunk in chunks
            chunks_dict[string(chunk.source.path)] = chunk
        end
        updated_content = update_changes!(tracker, chunks_dict)
        
        @test length(tracker.changes) == 2
        @test all(status -> status == :UNCHANGED, values(tracker.changes))
        
        # Modify one of the files
        write(file1_path, "Modified content for file 1")
        
        # Get chunks again
        chunks = get_chunks(chunker, file_paths)
        chunks_dict = OrderedDict{String, FileChunk}()
        for chunk in chunks
            chunks_dict[string(chunk.source.path)] = chunk
        end
        updated_content = update_changes!(tracker, chunks_dict)
        
        # Check that file1 is marked as UPDATED and file2 as UNCHANGED
        @test length(tracker.changes) == 2
        @test tracker.changes[file1_path] == :UPDATED
        @test tracker.changes[file2_path] == :UNCHANGED
        
        # Delete one file
        rm(file2_path)
        
        # Get chunks again - now only include file1
        chunks = get_chunks(chunker, [Path(file1_path)])
        chunks_dict = OrderedDict{String, FileChunk}()
        for chunk in chunks
            chunks_dict[string(chunk.source.path)] = chunk
        end
        updated_content = update_changes!(tracker, chunks_dict)
        
        # Check that file2 is removed from changes
        @test length(tracker.changes) == 1
        @test haskey(tracker.changes, file1_path)
        @test !haskey(tracker.changes, file2_path)
        
        # Clean up
        rm(temp_dir, recursive=true)
    end

    @testset "FileChunk comparison with whitespace differences" begin
        # Create a temporary file
        temp_dir = mktempdir()
        temp_file = joinpath(temp_dir, "whitespace_test.txt")
        
        # Write initial content
        write(temp_file, "Content with trailing space ")

        # Create two FileChunks with the same content but different whitespace
        source_path = SourcePath(path=temp_file)
        chunk1 = FileChunk(source=source_path, content="""
        Content with trailing space 
        """)
        chunk2 = FileChunk(source=source_path, content="Content with trailing space")
        
        # Test equality with our improved comparison
        @test chunk1 == chunk2
        
        # Test with ChangeTracker
        tracker = ChangeTracker{FileChunk}()
        src_content = OrderedDict{String,FileChunk}(
            temp_file => chunk1
        )
        
        # First update
        _ = update_changes!(tracker, src_content)
        @test tracker.changes[temp_file] == :NEW
        
        # Second update with slightly different whitespace
        src_content[temp_file] = chunk2
        _ = update_changes!(tracker, src_content)
        
        # Should be UNCHANGED despite whitespace differences
        @test tracker.changes[temp_file] == :UNCHANGED
        
        # Clean up
        rm(temp_dir, recursive=true)
    end
end
;