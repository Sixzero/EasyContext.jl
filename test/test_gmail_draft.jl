
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
        @test_throws ArgumentError("Email recipient (to) cannot be empty") create_gmail_draft(email_service, "", "Subject", "Body")
        @test_throws ArgumentError("Email subject cannot be empty") create_gmail_draft(email_service, "test@example.com", "", "Body")
        @test_throws ArgumentError("Email body cannot be empty") create_gmail_draft(email_service, "test@example.com", "Subject", "")
        @test_throws ArgumentError("Invalid email format for recipient") create_gmail_draft(email_service, "invalid_email", "Subject", "Body")
    end

    @testset "Long input handling" begin
        email_service = MockEmailService()
        long_subject = "a" ^ 999
        long_body = "a" ^ (25 * 1024 * 1024 + 1)
        @test_throws ArgumentError create_gmail_draft(email_service, "test@example.com", long_subject, "Body")
        @test_throws ArgumentError create_gmail_draft(email_service, "test@example.com", "Subject", long_body)
    end

    @testset "Special characters handling" begin
        email_service = MockEmailService()
        special_subject = "Special: !@#$%^&*()_+"
        special_body = "Body with üñîçødé characters: ñáéíóúäëïü"
        response = create_gmail_draft(email_service, "test@example.com", special_subject, special_body)
        raw_message = String(base64decode(response["message"]["raw"]))
        @test occursin(special_subject, raw_message)
        @test occursin(special_body, raw_message)
    end
end

