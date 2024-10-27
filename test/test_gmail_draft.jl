using Test
using Mocking

Mocking.activate()

# Mock the GoogleCloud module
mock_gmail_response = Dict("id" => "draft123", "message" => Dict("id" => "msg456"))
mock_gmail = @patch function Gmail(session)
    return (args...; kwargs...) -> mock_gmail_response
end

@testset "Gmail Draft Creation" begin
    apply(mock_gmail) do
        @testset "create_gmail_draft function" begin
            to = "test@example.com"
            subject = "Test Subject"
            body = "This is a test email body."

            response = create_gmail_draft(to, subject, body)

            @test response isa Dict
            @test haskey(response, "id")
            @test response["id"] == "draft123"
            @test haskey(response, "message")
            @test response["message"]["id"] == "msg456"
        end
    end
end
