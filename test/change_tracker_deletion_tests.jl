using Test
using DataStructures
using EasyContext: ChangeTracker, get_chunk_standard_format

@testset "ChangeTracker deletion tests" begin
    @testset "Verify complete key deletion" begin
        tracker = ChangeTracker()
        
        # Initial content
        src_content = OrderedDict{String,String}(
            "file1.txt" => "content1",
            "file2.txt" => "content2"
        )
        tracker(src_content)
        
        @test length(tracker.changes) == 2
        @test length(tracker.content) == 2
        
        # Remove one file
        new_content = OrderedDict{String,String}(
            "file1.txt" => "content1"
        )
        tracker(new_content)
        
        # Verify complete cleanup
        @test length(tracker.changes) == 1
        @test length(tracker.content) == 1
        @test !haskey(tracker.changes, "file2.txt")
        @test !haskey(tracker.content, "file2.txt")
        
        # Remove all files
        empty_content = OrderedDict{String,String}()
        tracker(empty_content)
        
        # Verify complete cleanup
        @test isempty(tracker.changes)
        @test isempty(tracker.content)
    end
    
    @testset "Multiple deletion cycles" begin
        tracker = ChangeTracker()
        
        # Cycle 1
        src1 = OrderedDict{String,String}("file1.txt" => "content1")
        tracker(src1)
        @test length(tracker.changes) == 1
        
        # Cycle 2  
        src2 = OrderedDict{String,String}("file2.txt" => "content2")
        tracker(src2)
        @test length(tracker.changes) == 1
        @test haskey(tracker.changes, "file2.txt")
        
        # Cycle 3
        src3 = OrderedDict{String,String}("file3.txt" => "content3")
        tracker(src3)
        @test length(tracker.changes) == 1
        @test haskey(tracker.changes, "file3.txt")
    end
end
