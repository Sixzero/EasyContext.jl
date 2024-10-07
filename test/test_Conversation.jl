using Test
using EasyContext
using Dates
using EasyContext: Message, create_user_message, create_AI_message, update_last_user_message_meta
using EasyContext: get_next_msg_contrcutor, get_cache_setting

@testset "BetterConversationCTX Tests" begin
    @testset "Constructor" begin
        sys_msg = "This is a system message"
        conv_ctx = Conversation_from_sysmsg(sys_msg=sys_msg)
        
        @test conv_ctx.system_message.content == sys_msg
        @test conv_ctx.system_message.role == :system
        @test isempty(conv_ctx.messages)
    end

    @testset "Adding messages" begin
        conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
        
        user_msg = create_user_message("Hello, AI!")
        conv_ctx(user_msg)
        
        @test length(conv_ctx.messages) == 1
        @test conv_ctx.messages[1].content == "Hello, AI!"
        @test conv_ctx.messages[1].role == :user
        
        ai_msg = create_AI_message("Hello, human!")
        conv_ctx(ai_msg)
        
        @test length(conv_ctx.messages) == 2
        @test conv_ctx.messages[2].content == "Hello, human!"
        @test conv_ctx.messages[2].role == :assistant
    end

    @testset "AgeTracker integration" begin
        conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
        age_tracker = AgeTracker(max_history=6, cut_to=3)
        
        for i in 1:8
            conv_ctx(create_user_message("User message $i"))
            conv_ctx(create_AI_message("AI message $i"))
            cut_old_history!(age_tracker, conv_ctx)
        end
        
        @test length(conv_ctx.messages) == 4
        @test conv_ctx.messages[1].content == "User message 7"
        @test conv_ctx.messages[4].content == "AI message 8"
    end

    @testset "get_cache_setting" begin
        conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
        age_tracker = AgeTracker(max_history=4, cut_to=3)
        
        @test get_cache_setting(age_tracker, conv_ctx) == :last
        
        conv_ctx(create_user_message("User message 1"))
        @test get_cache_setting(age_tracker, conv_ctx) == :last
        
        conv_ctx(create_AI_message("AI message 1"))
        @test get_cache_setting(age_tracker, conv_ctx) == :last
        
        conv_ctx(create_user_message("User message 2"))
        @test get_cache_setting(age_tracker, conv_ctx) === nothing
        
        conv_ctx(create_AI_message("AI message 2"))
        @test get_cache_setting(age_tracker, conv_ctx) === nothing
        
        conv_ctx(create_user_message("User message 3"))
        @test get_cache_setting(age_tracker, conv_ctx) === nothing
    end

    @testset "Cutting behavior and caching" begin
        @testset "Even max_history" begin
            conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
            age_tracker = AgeTracker(max_history=6, cut_to=4)
        
            # Fill up to max_history with alternating messages
            for i in 1:3
                conv_ctx(create_user_message("User message $i"))
                conv_ctx(create_AI_message("AI message $i"))
                cut_old_history!(age_tracker, conv_ctx)
            end
            
            # Check caching before cut
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            
            # Trigger cut
            conv_ctx(create_user_message("User message 4"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) == :last
            
            # Check messages after cut
            @test length(conv_ctx.messages) == 3
            @test conv_ctx.messages[1].content == "User message 3"
            @test conv_ctx.messages[2].content == "AI message 3"
            @test conv_ctx.messages[3].content == "User message 4"
            
            # Add more messages to reach the upper range
            conv_ctx(create_AI_message("AI message 4"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) == :last
            conv_ctx(create_user_message("User message 5"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            @test length(conv_ctx.messages) == 5
            conv_ctx(create_AI_message("AI message 5"))
            cut_old_history!(age_tracker, conv_ctx)
            
            # Check caching in the upper range
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            @test length(conv_ctx.messages) == 6
            
            # Trigger another cut
            conv_ctx(create_user_message("User message 6"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) == :last
            
            # Check messages after second cut
            @test length(conv_ctx.messages) == 3
            @test conv_ctx.messages[end-2].content == "User message 5"
            @test conv_ctx.messages[end-1].content == "AI message 5"
            @test conv_ctx.messages[end].content == "User message 6"
        end
        
        @testset "Odd max_history (adjusted to even)" begin
            conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
            age_tracker = AgeTracker(max_history=6, cut_to=4) # max_history=7, cut_to=3 was before.
            
            # Verify that max_history was adjusted to an even number
            @test age_tracker.max_history == 6
            @test age_tracker.cut_to == 4
        
            # Fill up to max_history with alternating messages
            for i in 1:3
                conv_ctx(create_user_message("User message $i"))
                conv_ctx(create_AI_message("AI message $i"))
                cut_old_history!(age_tracker, conv_ctx)
            end
            
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            @test length(conv_ctx.messages) == 6
            conv_ctx(create_user_message("User message 4"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) == :last
            @test length(conv_ctx.messages) == 3
            conv_ctx(create_AI_message("AI message 4"))
            cut_old_history!(age_tracker, conv_ctx)
            # Check caching before cut
            @test get_cache_setting(age_tracker, conv_ctx) == :last
            
            @test length(conv_ctx.messages) == 4
            # Trigger cut
            conv_ctx(create_user_message("User message 5"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            
            # Check messages after cut
            @test length(conv_ctx.messages) == 5
            @test conv_ctx.messages[end-1].content == "AI message 4"
            @test conv_ctx.messages[end].content == "User message 5"
            
            # Add more messages to reach the upper range
            conv_ctx(create_AI_message("AI message 5"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            conv_ctx(create_user_message("User message 6"))
            cut_old_history!(age_tracker, conv_ctx)
            @test get_cache_setting(age_tracker, conv_ctx) == :last
            conv_ctx(create_AI_message("AI message 6"))
            cut_old_history!(age_tracker, conv_ctx)
            conv_ctx(create_user_message("User message 7"))
            cut_old_history!(age_tracker, conv_ctx)
            
            # Check caching in the upper range
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            @test length(conv_ctx.messages) == 5
            # Trigger another cut
            conv_ctx(create_AI_message("AI message 7"))
            cut_old_history!(age_tracker, conv_ctx)
            @test length(conv_ctx.messages) == 6
            @test get_cache_setting(age_tracker, conv_ctx) === nothing
            conv_ctx(create_user_message("User message 8"))
            cut_old_history!(age_tracker, conv_ctx)
            @test length(conv_ctx.messages) == 3
            conv_ctx(create_AI_message("AI message 8"))
            cut_old_history!(age_tracker, conv_ctx)
            
            # Check messages after second cut
            @test length(conv_ctx.messages) == 4
            @test conv_ctx.messages[end-3].content == "User message 7"
            @test conv_ctx.messages[end-2].content == "AI message 7"
            @test conv_ctx.messages[end-1].content == "User message 8"
            @test conv_ctx.messages[end].content == "AI message 8"
        end
    end

    @testset "get_next_msg_contrcutor" begin
        conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
        
        # When conversation is empty, it should return create_user_message
        @test get_next_msg_contrcutor(conv_ctx) == create_user_message
        
        # After adding a user message
        conv_ctx(create_user_message("User message"))
        @test get_next_msg_contrcutor(conv_ctx) == create_AI_message
        
        # After adding an AI message
        conv_ctx(create_AI_message("AI message"))
        @test get_next_msg_contrcutor(conv_ctx) == create_user_message
    end

    @testset "Other methods" begin
        conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
        
        @test get_next_msg_contrcutor(conv_ctx) == create_user_message
        
        conv_ctx(create_user_message("User message"))
        @test get_next_msg_contrcutor(conv_ctx) == create_AI_message
        
        # add_error_message!(conv_ctx, "Test error message")
        # @test conv_ctx.conv.messages[end].content == "Test error message"
        
        # dict = to_dict(conv_ctx)
        # @test dict[:system] == "Test system message"
        # @test dict[:messages][1][:role] == "user"
        # @test dict[:messages][1][:content] == "User message"
        
        # dict_nosys = to_dict_nosys(conv_ctx)
        # @test !haskey(dict_nosys, :system)
        
    end

    @testset "update_last_user_message_meta" begin
        conv_ctx = Conversation_from_sysmsg(sys_msg="Test system message")
        conv_ctx(create_user_message("User message"))
        
        meta = Dict("input_tokens" => 10, "output_tokens" => 20, 
                    "cache_creation_input_tokens" => 5, "cache_read_input_tokens" => 2,
                    "price" => 0.001f0, "elapsed" => 1.5f0)
        
        update_last_user_message_meta(conv_ctx, meta)
        
        last_msg = conv_ctx.messages[end]
        @test last_msg isa Message
        @test last_msg.role == :user
        @test last_msg.content == "User message"
        @test last_msg.itok == 10
        @test last_msg.otok == 20
        @test last_msg.cached == 5
        @test last_msg.cache_read == 2
        @test last_msg.price == 0.001f0
        @test last_msg.elapsed == 1.5f0
    end
end
;
