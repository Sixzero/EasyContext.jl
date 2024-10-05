using HTTP
using RelevanceStacktrace
using JSON3
using URIs

function get_authorization_url()
    params = Dict(
        "client_id" => CLIENT_ID,
        "redirect_uri" => REDIRECT_URI,
        "scope" => SCOPE,
        "response_type" => "code",
        "access_type" => "offline"
    )
    return "https://accounts.google.com/o/oauth2/v2/auth?" * URIs.escapeuri(params)
end

function exchange_code_for_token(code)
    url = "https://oauth2.googleapis.com/token"
    headers = Dict("Content-Type" => "application/x-www-form-urlencoded")
    body = Dict(
        "client_id" => CLIENT_ID,
        "client_secret" => CLIENT_SECRET,
        "code" => code,
        "grant_type" => "authorization_code",
        "redirect_uri" => REDIRECT_URI
    )
    
    response = HTTP.post(url, headers=headers, body=URIs.escapeuri(body))
    
    if response.status == 200
        token_data = JSON3.read(response.body)
        return token_data.access_token, token_data.refresh_token
    else
        error("Token csere sikertelen: $(response.status)")
    end
end

function get_gmail_messages(access_token)
    url = "https://www.googleapis.com/gmail/v1/users/me/messages"
    headers = Dict("Authorization" => "Bearer $access_token")
    
    response = HTTP.get(url, headers=headers)
    
    if response.status == 200
        data = JSON3.read(response.body)
        messages = data.messages
        return messages
    else
        error("Hiba történt az üzenetek lekérdezésekor: $(response.status)")
    end
end

function get_message_details(access_token, message_id)
    url = "https://www.googleapis.com/gmail/v1/users/me/messages/$message_id"
    headers = Dict("Authorization" => "Bearer $access_token")
    
    response = HTTP.get(url, headers=headers)
    
    if response.status == 200
        data = JSON3.read(response.body)
        return data
    else
        error("Hiba történt az üzenet részleteinek lekérdezésekor: $(response.status)")
    end
end
