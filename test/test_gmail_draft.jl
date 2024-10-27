
using Test
using Mocking
using GoogleCloud
using Base64
using JSON3

Mocking.activate()

# Mock the GoogleCloud.Gmail module
mock_gmail_response = Dict("id" => "draft123", "message" => Dict("id" => "msg456"))
mock_gmail = @patch function GoogleCloud.Gmail(session)
    return function(args...; kwargs...)
        data = kwargs[:data]
        message = JSON3.read(base64decode(data["message"]["raw"]))
        return Dict(
            "id" => "draft123",
            "message" => Dict(
                "id" => "msg456",
                "raw" => data["message"]["raw"]
            )
        )
    end
end

# Import the create_gmail_draft function
include("../src/action/send_email.jl")

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

            # Verify the content of the draft email
            raw_message = base64decode(response["message"]["raw"])
            @test occursin("To: $to", raw_message)
            @test occursin("Subject: $subject", raw_message)
            @test occursin(body, raw_message)
        end

        @testset "Invalid input handling" begin
            @test_throws ArgumentError create_gmail_draft("", "Subject", "Body")
            @test_throws ArgumentError create_gmail_draft("test@example.com", "", "Body")
            @test_throws ArgumentError create_gmail_draft("test@example.com", "Subject", "")
        end

        @testset "API error handling" begin
            error_response = Dict("error" => Dict("message" => "API Error"))
            error_gmail = @patch function GoogleCloud.Gmail(session)
                return (args...; kwargs...) -> error_response
            end

            apply(error_gmail) do
                @test_throws ErrorException create_gmail_draft("test@example.com", "Subject", "Body")
            end
        end
    end
end

