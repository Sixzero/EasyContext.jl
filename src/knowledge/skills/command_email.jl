
const email_skill = Skill(
    name="EMAIL",
    skill_description="""
To create an email with a standardized format, use the EMAIL command:
<EMAIL to=recipient@example.com subject="Email Subject">
Dear Recipient,

[Email content here]

Best regards,
[Sender]
</EMAIL>
""",
    stop_sequence=""
)

@kwdef struct EmailCommand <: AbstractCommand
    id::UUID = uuid4()
    to::String
    subject::String
    content::String
    kwargs::Dict{String,String} = Dict{String,String}()
end

function EmailCommand(cmd::Command)
    EmailCommand(
        to=get(cmd.kwargs, "to", ""),
        subject=get(cmd.kwargs, "subject", ""),
        content=cmd.content,
        kwargs=cmd.kwargs
    )
end

execute(cmd::EmailCommand) = """
Sending email:
To: $(cmd.to)
Subject: $(cmd.subject)
Content:
$(cmd.content)
"""

