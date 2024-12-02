
@kwdef struct Command
    name::String
    args::Vector{String}
    kwargs::Dict{String,String}
    content::String
end

function parse_arguments(parts::Vector{SubString{String}})
  args = String[]
  kwargs = Dict{String,String}()
  
  for part in parts
      if contains(part, "=")
          key, value = split(part, "=")
          kwargs[key] = replace(value, "\""=>"")
      else
          push!(args, String(part))
      end
  end
  args, kwargs
end

function parse_command(text)
  lines = split(text, '\n')
  commands = Command[]
  current_command = nothing
  current_content = String[]
  
  for line in lines
      line = strip(line)
      isempty(line) && continue
      
      if startswith(line, '/') # Closing tag
          isnothing(current_command) && error("Found closing tag without opening tag: $line")
          command_name = line[2:end]
          command_name != current_command[1] && error("Mismatched tags: expected /$(current_command[1]), got /$command_name")
          
          push!(commands, Command(current_command[1], current_command[2], current_command[3], join(current_content, '\n')))
          current_command = nothing
          empty!(current_content)
      elseif !isnothing(current_command) # Content
          push!(current_content, line)
      else # Opening tag
          parts = split(line)
          command_name = parts[1]
          args, kwargs = length(parts) > 1 ? parse_arguments(parts[2:end]) : (String[], Dict{String,String}())
          current_command = (command_name, args, kwargs)
      end
  end
  
  !isnothing(current_command) && error("Unclosed tag: $(current_command[1])")
  commands
end
