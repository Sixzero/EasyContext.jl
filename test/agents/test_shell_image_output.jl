# Test: Shell command image output → ToolMessage with image_data
#
# Tests that when a shell command outputs a data URL image,
# the NativeExtractor produces a ToolMessage with image_data.

using Test
using EasyContext
using EasyContext: NativeExtractor, process_native_tool_calls!, collect_tool_messages
using OpenRouter: ToolMessage
using ToolCallFormat: resultimg2base64, decode_data_url
using Base64

# Generate data URL from actual PNG fixture
const TEST_PNG_PATH = joinpath(@__DIR__, "..", "fixtures", "red_1x1.png")
const TEST_PNG_B64 = base64encode(read(TEST_PNG_PATH))
const TEST_DATA_URL = "data:image/png;base64,$TEST_PNG_B64"

@testset "Shell Image Output" begin

    @testset "NativeExtractor produces ToolMessage with image_data" begin
        extractor = NativeExtractor([BashTool]; no_confirm=true)

        tool_calls = [Dict(
            "id" => "call_test_img",
            "type" => "function",
            "function" => Dict(
                "name" => "bash",
                "arguments" => """{"cmd": "printf '$TEST_DATA_URL'"}"""
            )
        )]

        process_native_tool_calls!(extractor, tool_calls, devnull)
        msgs = collect_tool_messages(extractor)

        @test length(msgs) == 1
        msg = msgs[1]
        @test msg isa ToolMessage
        @test msg.tool_call_id == "call_test_img"
        @test msg.image_data !== nothing
        @test length(msg.image_data) == 1
        @test startswith(msg.image_data[1], "data:image/png;base64,")

        # Verify it decodes to valid PNG
        raw = decode_data_url(msg.image_data[1])
        @test raw[1:4] == UInt8[0x89, 0x50, 0x4e, 0x47]  # PNG signature
    end

    @testset "NativeExtractor: non-image output has no image_data" begin
        extractor = NativeExtractor([BashTool]; no_confirm=true)

        tool_calls = [Dict(
            "id" => "call_test_text",
            "type" => "function",
            "function" => Dict(
                "name" => "bash",
                "arguments" => """{"cmd": "echo hello world"}"""
            )
        )]

        process_native_tool_calls!(extractor, tool_calls, devnull)
        msgs = collect_tool_messages(extractor)

        @test length(msgs) == 1
        @test msgs[1].image_data === nothing
    end

    @testset "NativeExtractor: mixed output has no image_data" begin
        extractor = NativeExtractor([BashTool]; no_confirm=true)

        tool_calls = [Dict(
            "id" => "call_test_mixed",
            "type" => "function",
            "function" => Dict(
                "name" => "bash",
                "arguments" => """{"cmd": "echo before; printf '$TEST_DATA_URL'"}"""
            )
        )]

        process_native_tool_calls!(extractor, tool_calls, devnull)
        msgs = collect_tool_messages(extractor)

        @test length(msgs) == 1
        # Mixed output should NOT match — regex requires entire output to be a single data URL
        @test msgs[1].image_data === nothing
    end

    @testset "E2E: LLM sees image from shell output" begin
        if get(ENV, "CI", "false") == "true"
            @info "Skipping LLM E2E test in CI"
            return
        end

        agent = create_FluidAgent("haiku";
            tools=[BashTool],
            extractor_type=NativeExtractor,
        )

        session = Session()
        push_message!(session, create_user_message(
            "Run this exact shell command and tell me what you see: printf '$(TEST_DATA_URL)'\nDescribe the image briefly."
        ))

        response = work(agent, session;
            no_confirm=true,
            quiet=true,
            io=devnull,
        )

        content = lowercase(response.content)
        @test any(w -> occursin(w, content), ["image", "red", "pixel", "png", "picture", "photo"])
    end
end
