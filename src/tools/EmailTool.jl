
@kwdef struct EmailTool <: AbstractTool
    id::UUID = uuid4()
    to::String
    subject::String
    content::String
end
function EmailTool(cmd::ToolTag)
    # Parse kwargs string into Dict
    kwargs_dict = Dict{String,String}()
    for pair in split(cmd.args, " ")
        key, value = split(pair, "=", limit=2)
        kwargs_dict[key] = strip(value, ['"', ' '])
    end
    
    EmailTool(
        to=get(kwargs_dict, "to", ""),
        subject=get(kwargs_dict, "subject", ""),
        content=cmd.content,
    )
end
instantiate(::Val{Symbol(EMAIL_TAG)}, cmd::ToolTag) = EmailTool(cmd)

commandname(cmd::Type{EmailTool}) = EMAIL_TAG
get_description(cmd::Type{EmailTool}) = """
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
stop_sequence(cmd::Type{EmailTool}) = STOP_SEQUENCE

# TODO: create the draft email in the email provider
execute(cmd::EmailTool) = """
Sending email:
To: $(cmd.to)
Subject: $(cmd.subject)
Content:
$(cmd.content)
"""

