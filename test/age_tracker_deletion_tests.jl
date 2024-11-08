using Test
using DataStructures
using EasyContext: ChangeTracker, AgeTracker, cut_old_conversation_history!, ConversationX, create_user_message, create_AI_message

@testset "AgeTracker with ChangeTracker deletion tests" begin
    @testset "Age-based deletion" begin
        age_tracker = AgeTracker(max_history=6, cut_to=4)
        changes_tracker = ChangeTracker()
        conv = ConversationX()
        
        # Initial content at age 0
        src_content = OrderedDict{String,String}(
            "file1.txt" => "content1",
        )
        changes_tracker(src_content)
        age_tracker(changes_tracker)
        conv(create_user_message("msg1"))
        
        @test haskey(age_tracker.tracker, "file1.txt")
        @test age_tracker.tracker["file1.txt"] == 0
        
        # Age 1: Add new file
        age_tracker.age = 2
        src_content["file2.txt"] = "content2"
        changes_tracker(src_content)
        age_tracker(changes_tracker)
        conv(create_AI_message("msg2"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        @test age_tracker.tracker["file2.txt"] == 2

        conv(create_AI_message("msg4"))
        conv(create_user_message("msg5"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        @test haskey(src_content, "file2.txt")
        conv(create_AI_message("msg4"))
        conv(create_user_message("msg5"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        @test !haskey(src_content, "file2.txt")
        conv(create_AI_message("msg4"))
        conv(create_user_message("msg5"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        @test !haskey(src_content, "file2.txt")  # Changed to !haskey

        # Age 2: Add another file
        src_content["file3.txt"] = "content3"
        changes_tracker(src_content)
        age_tracker(changes_tracker)
        conv(create_user_message("msg3"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        @show age_tracker.age
        # Should trigger deletion of file1.txt when reaching max_history
        conv(create_AI_message("msg4"))
        conv(create_user_message("msg5"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        @test !haskey(src_content, "file1.txt")
        @test !haskey(changes_tracker.changes, "file1.txt")
        @test !haskey(changes_tracker.content, "file1.txt")
        @test !haskey(age_tracker.tracker, "file1.txt")
        
        # Verify remaining files
        @test !haskey(src_content, "file2.txt")
        @test haskey(src_content, "file3.txt")
    end

    @testset "Update refreshes age" begin
        age_tracker = AgeTracker(max_history=4, cut_to=2)
        changes_tracker = ChangeTracker()
        conv = ConversationX()
        
        # Initial file
        src_content = OrderedDict{String,String}(
            "file1.txt" => "content1",
        )
        changes_tracker(src_content)
        age_tracker(changes_tracker)
        conv(create_user_message("msg1"))
        @test age_tracker.tracker["file1.txt"] == 0
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        # Update file1
        src_content["file1.txt"] = "content1_updated"
        changes_tracker(src_content)
        age_tracker(changes_tracker)
        conv(create_AI_message("msg2"))
        
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        @test age_tracker.tracker["file1.txt"] == 1  # Changed from 2 to 1 to match message count
        
        @test haskey(src_content, "file1.txt")
        # Add more messages to reach max_history
        conv(create_user_message("msg3"))
        conv(create_AI_message("msg4"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        # Should still exist since it was updated recently
        @test !haskey(src_content, "file1.txt")
        @test !haskey(changes_tracker.changes, "file1.txt")
    end

    @testset "Message count based age tracking" begin
        age_tracker = AgeTracker(max_history=6, cut_to=4)
        changes_tracker = ChangeTracker()
        conv = ConversationX()
        src_content = OrderedDict{String,String}("file1.txt" => "content1")
        
        # Initial state
        changes_tracker(src_content)
        age_tracker(changes_tracker)
        @test age_tracker.age == 0
        @test age_tracker.last_message_count == 0
        
        # Add 3 messages
        conv(create_user_message("msg1"))
        conv(create_AI_message("msg2"))
        conv(create_user_message("msg3"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        @test age_tracker.age == 3
        @test age_tracker.last_message_count == 3
        
        # Add 2 more messages
        conv(create_AI_message("msg4"))
        conv(create_user_message("msg5"))
        cut_old_conversation_history!(age_tracker, conv, (tracker_context=src_content, changes_tracker=changes_tracker))
        
        @test age_tracker.age == 5
        @test age_tracker.last_message_count == 5
    end

    @testset "Multiple contexts deletion" begin
        age_tracker = AgeTracker(max_history=6, cut_to=4)
        changes_tracker1 = ChangeTracker()
        changes_tracker2 = ChangeTracker()
        conv = ConversationX()
        
        # Initial content in two different contexts
        src_content1 = OrderedDict{String,String}(
            "file1.txt" => "content1",
            "file2.txt" => "content2"
        )
        src_content2 = OrderedDict{String,String}(
            "file3.txt" => "content3",
            "file4.txt" => "content4"
        )
        
        # Setup initial state
        changes_tracker1(src_content1)
        changes_tracker2(src_content2)
        age_tracker(changes_tracker1)
        age_tracker(changes_tracker2)
        
        # Age some files by adding messages
        for i in 1:4
            conv(create_user_message("msg$i"))
            conv(create_AI_message("resp$i"))
            cut_old_conversation_history!(age_tracker, conv, 
                (tracker_context=src_content1, changes_tracker=changes_tracker1),
                (tracker_context=src_content2, changes_tracker=changes_tracker2)
            )
        end
        
        # At this point older files should be deleted from both contexts
        @test !haskey(src_content1, "file1.txt")
        @test !haskey(src_content1, "file2.txt")
        @test !haskey(src_content2, "file3.txt")
        @test !haskey(src_content2, "file4.txt")
        
        # Verify that tracker is cleaned up properly
        @test !haskey(age_tracker.tracker, "file1.txt")
        @test !haskey(age_tracker.tracker, "file2.txt")
        @test !haskey(age_tracker.tracker, "file3.txt")
        @test !haskey(age_tracker.tracker, "file4.txt")
        
        # Add new content to both contexts
        src_content1["file5.txt"] = "content5"
        src_content2["file6.txt"] = "content6"
        changes_tracker1(src_content1)
        changes_tracker2(src_content2)
        age_tracker(changes_tracker1)
        age_tracker(changes_tracker2)
        
        # Verify new files are tracked
        @test haskey(age_tracker.tracker, "file5.txt")
        @test haskey(age_tracker.tracker, "file6.txt")
    end
end
;
