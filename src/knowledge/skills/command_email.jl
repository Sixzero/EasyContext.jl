

const email_skill = Skill(
    name=EMAIL_TAG,
    description="""
To create an email with a standardized format, use the $(EMAIL_TAG) command:
<$(EMAIL_TAG) to=recipient@example.com subject="Email Subject">
Dear Recipient,

[Email content here]

Best regards,
[Sender]
</$(EMAIL_TAG)>
""",
    stop_sequence=""
)

@kwdef struct EmailCommand <: AbstractCommand
    id::UUID = uuid4()
    to::String
    subject::String
    content::String
end
has_stop_sequence(cmd::EmailCommand) = false

function EmailCommand(cmd::Command)
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

execute(cmd::EmailCommand) = """
Sending email:
To: $(cmd.to)
Subject: $(cmd.subject)
Content:
$(cmd.content)
"""

