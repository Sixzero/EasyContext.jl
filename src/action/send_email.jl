
using GoogleCloud.Gmail
using Base64

function create_gmail_draft(to::String, subject::String, body::String)
    isempty(to) && throw(ArgumentError("Email recipient (to) cannot be empty"))
    isempty(subject) && throw(ArgumentError("Email subject cannot be empty"))
    isempty(body) && throw(ArgumentError("Email body cannot be empty"))

    # Initialize the Gmail service
    session = GoogleSession(
        GoogleCredentials(
            ENV["GOOGLE_APPLICATION_CREDENTIALS"],
            ["https://www.googleapis.com/auth/gmail.compose"]
        )
    )
    gmail = Gmail(session)

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
    draft = Dict("message" => message)
    response = gmail(:users=>:drafts=>:create; userId="me", data=draft)

    # Check for API errors
    if haskey(response, "error")
        throw(ErrorException("Gmail API Error: $(response["error"]["message"])"))
    end

    return response
end

