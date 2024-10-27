
using Test
using Base64
include("../src/action/send_email.jl")

@testset "Email Draft Creation" begin
    @testset "create_gmail_draft function" begin
        email_service = MockEmailService()
        to = "test@example.com"
        subject = "Test Subject"
        body = "This is a test email body."

        response = create_gmail_draft(email_service, to, subject, body)

        @test response isa Dict
        @test haskey(response, "id")
        @test response["id"] == "draft123"
        @test haskey(response, "message")
        @test response["message"]["id"] == "msg456"

        # Verify the content of the draft email
        raw_message = String(base64decode(response["message"]["raw"]))
        @test occursin("To: $to", raw_message)
        @test occursin("Subject: $subject", raw_message)
        @test occursin(body, raw_message)
    end

    @testset "Invalid input handling" begin
        email_service = MockEmailService()
        @test_throws ArgumentError create_gmail_draft(email_service, "", "Subject", "Body")
        @test_throws ArgumentError create_gmail_draft(email_service, "test@example.com", "", "Body")
        @test_throws ArgumentError create_gmail_draft(email_service, "test@example.com", "Subject", "")
    end

end

