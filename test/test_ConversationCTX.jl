using Test
using EasyContext
using Dates
using EasyContext: get_next_msg_contrcutor, get_cache_setting, add_error_message!
using EasyContext: to_dict, to_dict_nosys, update_last_user_message_meta

@testset "ConversationCTX Tests" begin
    @testset "Constructor" begin
        sys_msg = "This is a system message"
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg=sys_msg)
        
        @test conv_ctx isa ConversationCTX
        @test conv_ctx.conv.system_message.content == sys_msg
        @test conv_ctx.conv.system_message.role == :system
        @test isempty(conv_ctx.conv.messages)
        @test conv_ctx.max_history == 10
    end

    @testset "Adding messages" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message")
        
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

    @testset "Max history limit" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message", max_history=3)
        
        for i in 1:5
            conv_ctx(create_user_message("User message $i"))
            conv_ctx(create_AI_message("AI message $i"))
        end
        
        @test length(conv_ctx.conv.messages) == 3
        @test conv_ctx.conv.messages[1].content == "User message 4"
        @test conv_ctx.conv.messages[3].content == "AI message 5"
    end

    @testset "get_cache_setting" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message", max_history=5)
        
        @test get_cache_setting(conv_ctx) == :all
        
        for i in 1:3
            conv_ctx(create_user_message("User message $i"))
            conv_ctx(create_AI_message("AI message $i"))
        end
        
        @test get_cache_setting(conv_ctx) === nothing
    end

    @testset "add_error_message!" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message")
        
        add_error_message!(conv_ctx, "Test error message")
        
        @test length(conv_ctx.conv.messages) == 1
        @test conv_ctx.conv.messages[1].content == "Test error message"
        @test conv_ctx.conv.messages[1].role == :user
    end

    @testset "get_next_msg_contrcutor" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message")
        
        @test get_next_msg_contrcutor(conv_ctx) == create_user_message
        
        conv_ctx(create_user_message("User message"))
        @test get_next_msg_contrcutor(conv_ctx) == create_AI_message
        
        conv_ctx(create_AI_message("AI message"))
        @test get_next_msg_contrcutor(conv_ctx) == create_user_message
    end

    @testset "to_dict functions" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message")
        conv_ctx(create_user_message("User message"))
        conv_ctx(create_AI_message("AI message"))
        
        dict = to_dict(conv_ctx)
        @test dict[:system] == "Test system message"
        @test dict[:messages][1][:role] == "user"
        @test dict[:messages][1][:content] == "User message"
        @test dict[:messages][2][:role] == "assistant"
        @test dict[:messages][2][:content] == "AI message"
        
        dict_nosys = to_dict_nosys(conv_ctx)
        @test !haskey(dict_nosys, :system)
        @test length(dict_nosys[:messages]) == 2
        
        dict_nosys_detailed = to_dict_nosys_detailed(conv_ctx)
        @test !haskey(dict_nosys_detailed, :system)
        @test haskey(dict_nosys_detailed[:messages][1], :timestamp)
    end

    @testset "update_last_user_message_meta" begin
        conv_ctx = ConversationCTX_from_sysmsg(sys_msg="Test system message")
        conv_ctx(create_user_message("User message"))
        
        meta = Dict("input_tokens" => 10, "output_tokens" => 20, 
                    "cache_creation_input_tokens" => 5, "cache_read_input_tokens" => 2,
                    "price" => 0.001, "elapsed" => 1.5)
        
        update_last_user_message_meta(conv_ctx, meta)
        
        last_msg = conv_ctx.conv.messages[end]
        @test last_msg.input_tokens == 10
        @test last_msg.output_tokens == 20
        @test last_msg.cache_creation_input_tokens == 5
        @test last_msg.cache_read_input_tokens == 2
        @test last_msg.price == 0.001
        @test last_msg.elapsed == 1.5
    end
end
;