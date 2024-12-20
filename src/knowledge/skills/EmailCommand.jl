
@kwdef struct EmailCommand <: AbstractCommand
    id::UUID = uuid4()
    to::String
    subject::String
    content::String
end
function EmailCommand(cmd::CommandTag)
    # Parse kwargs string into Dict
    kwargs_dict = Dict{String,String}()
    for pair in split(cmd.args, " ")
        key, value = split(pair, "=", limit=2)
        kwargs_dict[key] = strip(value, ['"', ' '])
    end
    
    EmailCommand(
        to=get(kwargs_dict, "to", ""),
        subject=get(kwargs_dict, "subject", ""),
        content=cmd.content,
    )
end
instantiate(::Val{Symbol(EMAIL_TAG)}, cmd::CommandTag) = EmailCommand(cmd)

commandname(cmd::Type{EmailCommand}) = EMAIL_TAG
get_description(cmd::Type{EmailCommand}) = """
To create an email with a standardized format, use the $(EMAIL_TAG) command:
$(EMAIL_TAG) to=recipient@example.com subject="Email Subject"
Dear Recipient,

[Email content here]

Best,
[Sender]
$(END_OF_BLOCK_TAG)
or 
$(email_format("to@recipient.com", "Topic subject", "Email content here"))
"""
stop_sequence(cmd::Type{EmailCommand}) = STOP_SEQUENCE

# TODO: create the draft email in the email provider
execute(cmd::EmailCommand) = """
Sending email:
To: $(cmd.to)
Subject: $(cmd.subject)
Content:
$(cmd.content)
"""

