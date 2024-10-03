using Test
using EasyContext
using Dates
using EasyContext: Message, create_user_message, create_AI_message, update_last_user_message_meta

@testset "BetterConversationCTX Tests" begin
    @testset "Constructor" begin
        sys_msg = "This is a system message"
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg=sys_msg)
        
        @test conv_ctx isa BetterConversationCTX
        @test conv_ctx.conv.system_message.content == sys_msg
        @test conv_ctx.conv.system_message.role == :system
        @test isempty(conv_ctx.conv.messages)
        @test conv_ctx.max_history == 14
        @test conv_ctx.cut_to == 7
    end

    @testset "Adding messages" begin
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message")
        
        user_msg = create_user_message("Hello, AI!")
        conv_ctx(user_msg)
        
        @test length(conv_ctx.conv.messages) == 1
        @test conv_ctx.conv.messages[1].content == "Hello, AI!"
        @test conv_ctx.conv.messages[1].role == :user
        
        ai_msg = create_AI_message("Hello, human!")
        conv_ctx(ai_msg)
        
        @test length(conv_ctx.conv.messages) == 2
        @test conv_ctx.conv.messages[2].content == "Hello, human!"
        @test conv_ctx.conv.messages[2].role == :assistant
    end

    @testset "Max history limit and cutting" begin
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message", max_history=6, cut_to=3)
        
        for i in 1:8
            conv_ctx(create_user_message("User message $i"))
            conv_ctx(create_AI_message("AI message $i"))
        end
        
        @test length(conv_ctx.conv.messages) == 4
        @test conv_ctx.conv.messages[1].content == "User message 7"
        @test conv_ctx.conv.messages[4].content == "AI message 8"
    end

    @testset "get_cache_setting" begin
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message", max_history=5, cut_to=3)
        
        @test get_cache_setting(conv_ctx) == :last
        
        conv_ctx(create_user_message("User message 1"))
        conv_ctx(create_AI_message("AI message 1"))
        @test get_cache_setting(conv_ctx) == :last
        
        conv_ctx(create_user_message("User message 2"))
        @test get_cache_setting(conv_ctx) == :last
        
        conv_ctx(create_AI_message("AI message 2"))
        @test get_cache_setting(conv_ctx) == :last
        
        conv_ctx(create_user_message("User message 2"))
        @test get_cache_setting(conv_ctx) == nothing
    end

    @testset "Cutting behavior and caching" begin
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message", max_history=6, cut_to=3)
    
        # Fill up to max_history
        for i in 1:6
            conv_ctx(create_user_message("User message $i"))
        end
        
        # Check caching before cut
        @test get_cache_setting(conv_ctx) === nothing
        
        # Trigger cut
        conv_ctx(create_user_message("User message 7"))
        @test get_cache_setting(conv_ctx) === :last
        
        # Check messages after cut
        @test length(conv_ctx.conv.messages) == 3
        @test conv_ctx.conv.messages[1].content == "User message 5"
        @test conv_ctx.conv.messages[2].content == "User message 6"
        @test conv_ctx.conv.messages[3].content == "User message 7"
        
        # Check caching after cut
        @test get_cache_setting(conv_ctx) == :last
        # Add more messages to reach the upper range
        conv_ctx(create_user_message("User message 8"))
        @test length(conv_ctx.conv.messages) == 4
        @test get_cache_setting(conv_ctx) == :last
        conv_ctx(create_user_message("User message 9"))
        
        # Check caching in the upper range
        @test get_cache_setting(conv_ctx) == :last
        
        # Trigger another cut
        conv_ctx(create_user_message("User message 10"))
        @test get_cache_setting(conv_ctx) == nothing
        conv_ctx(create_user_message("User message 11"))
        @test get_cache_setting(conv_ctx) == :last
        
        # Check messages after second cut
        @test length(conv_ctx.conv.messages) == 3
        @test conv_ctx.conv.messages[1].content == "User message 9"
        @test conv_ctx.conv.messages[2].content == "User message 10"
        @test conv_ctx.conv.messages[3].content == "User message 11"
        
        # Check caching after second cut
        @test get_cache_setting(conv_ctx) == :last
    end

    @testset "get_next_msg_contrcutor" begin
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message")
        
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
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message")
        
        @test get_next_msg_contrcutor(conv_ctx) == create_user_message
        
        conv_ctx(create_user_message("User message"))
        @test get_next_msg_contrcutor(conv_ctx) == create_AI_message
        
        add_error_message!(conv_ctx, "Test error message")
        @test conv_ctx.conv.messages[end].content == "Test error message"
        
        # dict = to_dict(conv_ctx)
        # @test dict[:system] == "Test system message"
        # @test dict[:messages][1][:role] == "user"
        # @test dict[:messages][1][:content] == "User message"
        
        # dict_nosys = to_dict_nosys(conv_ctx)
        # @test !haskey(dict_nosys, :system)
        
    end

    @testset "update_last_user_message_meta" begin
        conv_ctx = BetterConversationCTX_from_sysmsg(sys_msg="Test system message")
        conv_ctx(create_user_message("User message"))
        
        meta = Dict("input_tokens" => 10, "output_tokens" => 20, 
                    "cache_creation_input_tokens" => 5, "cache_read_input_tokens" => 2,
                    "price" => 0.001f0, "elapsed" => 1.5f0)
        
        update_last_user_message_meta(conv_ctx, meta)
        
        last_msg = conv_ctx.conv.messages[end]
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
