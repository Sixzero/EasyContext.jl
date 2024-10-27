
using Base64
using HTTP
using JSON3

abstract type AbstractEmailService end

struct GmailService <: AbstractEmailService
    access_token::String
end

"""
    create_gmail_draft(email_service::GmailService, to::String, subject::String, body::String)

Create a new Gmail draft message.

# Arguments
- `email_service::GmailService`: The Gmail service object with access token.
- `to::String`: The recipient's email address.
- `subject::String`: The email subject.
- `body::String`: The email body content.

# Returns
A dictionary containing the draft message details.

# Throws
- `ArgumentError`: If any of the input parameters are invalid.
- `HTTP.ExceptionRequest.StatusError`: If the API request fails.
"""
function create_gmail_draft(email_service::GmailService, to::String, subject::String, body::String)
    isempty(to) && throw(ArgumentError("Email recipient (to) cannot be empty"))
    isempty(subject) && throw(ArgumentError("Email subject cannot be empty"))
    isempty(body) && throw(ArgumentError("Email body cannot be empty"))

    # Validate email format
    if !occursin(r"^[^@]+@[^@]+\.[^@]+$", to)
        throw(ArgumentError("Invalid email format for recipient"))
    end

    # Limit subject and body length
    max_subject_length = 998  # RFC 2822 recommended limit
    max_body_length = 25 * 1024 * 1024  # 25MB limit for Gmail

    if length(subject) > max_subject_length
        throw(ArgumentError("Subject exceeds maximum length of $max_subject_length characters"))
    end

    if length(body) > max_body_length
        throw(ArgumentError("Body exceeds maximum length of $max_body_length bytes"))
    end

    # Prepare the email message
    message = Dict(
        "raw" => base64encode("""
        From: me
        To: $to
        Subject: $subject

        $body
        """)
    )

    # Create the draft
    response = send_draft(email_service, message)

    return response
end

"""
    send_draft(email_service::GmailService, message::Dict)

Send a draft message to the Gmail API.

# Arguments
- `email_service::GmailService`: The Gmail service object with access token.
- `message::Dict`: The message content as a dictionary.

# Returns
A dictionary containing the API response.

# Throws
- `HTTP.ExceptionRequest.StatusError`: If the API request fails.
"""
function send_draft(email_service::GmailService, message::Dict)
    url = "https://www.googleapis.com/gmail/v1/users/me/drafts"
    headers = Dict(
        "Authorization" => "Bearer $(email_service.access_token)",
        "Content-Type" => "application/json"
    )
    body = JSON3.write(Dict("message" => message))

    response = HTTP.post(url, headers, body)
    return JSON3.read(response.body, Dict)
end

"""
    send_gmail_message(email_service::GmailService, draft_id::String)

Send a Gmail message from an existing draft.

# Arguments
- `email_service::GmailService`: The Gmail service object with access token.
- `draft_id::String`: The ID of the draft to send.

# Returns
A dictionary containing the sent message details.

# Throws
- `HTTP.ExceptionRequest.StatusError`: If the API request fails.
"""
function send_gmail_message(email_service::GmailService, draft_id::String)
    url = "https://www.googleapis.com/gmail/v1/users/me/drafts/$(draft_id)/send"
    headers = Dict(
        "Authorization" => "Bearer $(email_service.access_token)",
        "Content-Type" => "application/json"
    )

    response = HTTP.post(url, headers)
    return JSON3.read(response.body, Dict)
end

"""
    get_gmail_draft(email_service::GmailService, draft_id::String)

Retrieve a Gmail draft message.

# Arguments
- `email_service::GmailService`: The Gmail service object with access token.
- `draft_id::String`: The ID of the draft to retrieve.

# Returns
A dictionary containing the draft message details.

# Throws
- `HTTP.ExceptionRequest.StatusError`: If the API request fails.
"""
function get_gmail_draft(email_service::GmailService, draft_id::String)
    url = "https://www.googleapis.com/gmail/v1/users/me/drafts/$(draft_id)"
    headers = Dict(
        "Authorization" => "Bearer $(email_service.access_token)"
    )

    response = HTTP.get(url, headers)
    return JSON3.read(response.body, Dict)
end

