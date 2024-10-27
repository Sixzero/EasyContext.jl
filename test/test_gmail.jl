
# Ezeket az adatokat a környezeti változókból olvassuk be
const CLIENT_ID = get(ENV, "GMAIL_CLIENT_ID", "")
const CLIENT_SECRET = get(ENV, "GMAIL_CLIENT_SECRET", "")
const REDIRECT_URI = get(ENV, "GMAIL_REDIRECT_URI", "http://localhost:8080/callback")
const SCOPE = "https://www.googleapis.com/auth/gmail.readonly"

println("Kérjük, látogasson el erre az URL-re és engedélyezze az alkalmazást:")
println(get_authorization_url())

println("\nAdja meg a visszakapott kódot:")
auth_code = readline()

access_token, refresh_token = exchange_code_for_token(auth_code)
println("Access Token megszerezve.")

messages = get_gmail_messages(access_token)
println("Üzenetek száma: $(length(messages))")

# Az első 5 üzenet részleteinek lekérdezése
for (i, message) in enumerate(messages[1:min(10, length(messages))])
    details = get_message_details(access_token, message.id)
    subject = ""
    from = ""
    for header in details.payload.headers
        if header.name == "Subject"
            subject = header.value
        elseif header.name == "From"
            from = header.value
        end
    end
    println("Message $i ID: $(message.id)")
    println("  Feladó: $from")
    println("  Tárgy: $subject")
    println()
end

println("Refresh Token (biztonságosan tárolja): $refresh_token")
