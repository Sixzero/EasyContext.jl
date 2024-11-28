@kwdef struct Tag
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

function parse_tag(text)
  lines = split(text, '\n')
  tags = Tag[]
  current_tag = nothing
  current_content = String[]
  
  for line in lines
      line = strip(line)
      isempty(line) && continue
      
      if startswith(line, '/') # Closing tag
          isnothing(current_tag) && error("Found closing tag without opening tag: $line")
          tag_name = line[2:end]
          tag_name != current_tag[1] && error("Mismatched tags: expected /$(current_tag[1]), got /$tag_name")
          
          push!(tags, Tag(current_tag[1], current_tag[2], current_tag[3], join(current_content, '\n')))
          current_tag = nothing
          empty!(current_content)
      elseif !isnothing(current_tag) # Content
          push!(current_content, line)
      else # Opening tag
          parts = split(line)
          tag_name = parts[1]
          args, kwargs = length(parts) > 1 ? parse_arguments(parts[2:end]) : (String[], Dict{String,String}())
          current_tag = (tag_name, args, kwargs)
      end
  end
  
  !isnothing(current_tag) && error("Unclosed tag: $(current_tag[1])")
  tags
end