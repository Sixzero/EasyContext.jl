using UUIDs
using OrderedCollections
using PromptingTools
using PromptingTools: aigenerate

export FluidAgent, execute_tools!

"""
FluidAgent manages a set of tools and executes them using LLM guidance.
"""
@kwdef mutable struct FluidAgent
    tools::Vector{Type{<:AbstractTool}} 
    model::String = "claude"
    workspace::String = pwd()
    tool_map::Dict{String,Type{<:AbstractTool}} = Dict(toolname(T) => T for T in tools)
end

# Constructor with tuple of tools
FluidAgent(tools::Tuple, args...; kwargs...) = FluidAgent(collect(tools), args...; kwargs...)

"""
Get tool descriptions for system prompt
"""
function get_tool_descriptions(agent::FluidAgent)
    descriptions = ["Available tools:"]
    for tool in agent.tools
        push!(descriptions, get_description(tool))
    end
    join(descriptions, "\n\n")
end

"""
Parse tool calls from LLM response
"""
function parse_tools(content::String)
    tags = ToolTag[]
    lines = split(content, '\n')
    i = 1
    while i <= length(lines)
        line = strip(lines[i])
        
        # Single line tools
        if any(startswith.(line, [CLICK_TAG, SENDKEY_TAG, CATFILE_TAG]))
            tag_end = findfirst(' ', line)
            name = line[1:something(tag_end, length(line))]
            args = isnothing(tag_end) ? "" : line[tag_end+1:end]
            push!(tags, ToolTag(name=name, args=args))
            i += 1
            continue
        end
        
        # Multi-line tools
        if any(startswith.(line, [MODIFY_FILE_TAG, CREATE_FILE_TAG, SHELL_BLOCK_TAG]))
            tag_end = findfirst(' ', line)
            name = line[1:something(tag_end, length(line))]
            args = isnothing(tag_end) ? "" : line[tag_end+1:end]
            
            # Find content block
            content = ""
            i += 1
            while i <= length(lines) && !startswith(lines[i], "```endblock")
                content *= lines[i] * "\n"
                i += 1
            end
            
            push!(tags, ToolTag(
                name=name,
                args=args,
                content=content,
                kwargs=Dict("root_path" => agent.workspace)
            ))
        end
        i += 1
    end
    tags
end

"""
Create tool instance from tag using memoized mapping
"""
function create_tool(agent::FluidAgent, tag::ToolTag)
    haskey(agent.tool_map, tag.name) || throw(KeyError("Unknown tool: $(tag.name)"))
    agent.tool_map[tag.name](tag)
end

"""
Execute a single tool
"""
function execute_tool!(agent::FluidAgent, tool::AbstractTool; no_confirm=false)
    result = execute(tool; no_confirm)
    result
end

"""
Process and execute tools in order while allowing parallel preprocessing
"""
function process_tools!(content::String, agent::FluidAgent; no_confirm=false)
    tags = parse_tools(content)
    isempty(tags) && return OrderedDict{UUID,String}()
    
    # Start preprocessing tasks
    preprocess_tasks = OrderedDict{UUID,Tuple{AbstractTool,Task}}()
    for tag in tags
        tool = create_tool(agent, tag)
        preprocess_tasks[tool.id] = (tool, @async preprocess(tool))
    end
    
    # Execute tools in order, after their preprocessing completes
    results = OrderedDict{UUID,String}()
    for (id, (tool, prep_task)) in preprocess_tasks
        try
            preprocessed_tool = fetch(prep_task)
            results[id] = execute(preprocessed_tool; no_confirm)
        catch e
            @error "Tool execution failed" tool=tool exception=(e, catch_backtrace())
            results[id] = "Error: $(sprint(showerror, e))"
        end
    end
    
    results
end

"""
Get formatted tool results for LLM context
"""
function get_tool_context(agent::FluidAgent)
    isempty(agent.tool_results) && return ""
    
    output = "Previous tool results:\n"
    for (id, result) in agent.tool_results
        output *= "- $result\n"
    end
    output
end

"""
Generate system prompt for LLM
"""
function get_system_prompt(agent::FluidAgent)
    """
    You are an AI assistant that can use tools to help accomplish tasks.
    
    $(get_tool_descriptions(agent))
    
    Always format tool calls exactly as shown in the examples.
    Wait for tool results before proceeding with dependent steps.
    """
end

"""
Run an LLM interaction with tool execution
Returns both the LLM response and tool results
"""
function run(agent::FluidAgent, user_input::String; no_confirm=false)
    # Generate LLM response
    response = aigenerate(
        get_system_prompt(agent),
        user_input;
        model=agent.model
    )
    # Process tools and collect results
    results = process_tools!(response.content, agent; no_confirm)
    
    # Return both response and results
    (content=response.content, results=results)
end
