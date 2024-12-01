@kwdef struct Skill
	name::String=""
	skill_description::String
	stop_signal::String
	parser::Function
	action::Function
	blocking::Bool
end

function parse_streaming(io::IO)
	buffer = IOBuffer()
	pattern = r"(?<field1>\w+)\s+(?<field2>\d+)\s+(?<field3>[^\n]+)"

	while !eof(io)
			write(buffer, read(io, 1024))
			seek(buffer, 0)
			data = String(take!(buffer))

			last_index = 1
			for match in eachmatch(pattern, data)
					# Process match
					last_index = match.offset + match.match.length
			end

			# Retain unprocessed data
			write(buffer, data[last_index:end])
	end
end


struct Click
	button::Symbol
	x::Int
	y::Int
end

ClickSkill = Skill(name="Click", 
										skill_description="Click on the given coordinates", 
										stop_signal="", 
										parser=(str) -> begin
											lines = split(str, "\n")
											click = Click(lines[end])
										end, 
										action=(click) -> begin
											doclick(click)
										end, 
										blocking=true)
