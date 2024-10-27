
using Base64

abstract type AbstractEmailService end

struct MockEmailService <: AbstractEmailService end

function create_gmail_draft(email_service::AbstractEmailService, to::String, subject::String, body::String)
    isempty(to) && throw(ArgumentError("Email recipient (to) cannot be empty"))
    isempty(subject) && throw(ArgumentError("Email subject cannot be empty"))
    isempty(body) && throw(ArgumentError("Email body cannot be empty"))

    # Prepare the email message
    message = Dict(
        "raw" => base64encode("""
        From: me
        To: $to
        Subject: $subject

        $body
        """)
    )

    # Create the draft (this would be implemented differently for each email service)
    response = send_draft(email_service, message)

    # Check for API errors
    if haskey(response, "error")
        throw(ErrorException("Email API Error: $(response["error"]["message"])"))
    end

    return response
end

# Mock implementation for testing
function send_draft(::MockEmailService, message::Dict)
    # Simulate API response
    return Dict(
        "id" => "draft123",
        "message" => Dict(
            "id" => "msg456",
            "raw" => message["raw"]
        )
    )
end

