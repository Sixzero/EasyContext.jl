
using GoogleCloud

function create_gmail_draft(to::String, subject::String, body::String)
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

    return response
end

