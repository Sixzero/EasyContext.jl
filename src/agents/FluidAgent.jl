using UUIDs
using PromptingTools
using PromptingTools: aigenerate

export FluidAgent, execute_tools, work

"""
FluidAgent manages a set of tools and executes them using LLM guidance.
"""
@kwdef mutable struct FluidAgent
    tools::Vector{Type{<:AbstractTool}} 
    model::String = "claude"
    workspace::String = pwd()
    tool_map::Dict{String,Type{<:AbstractTool}} = Dict(toolname(T) => T for T in tools)
    extractor = ToolTagExtractor()
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
Returns both the full and truncated context strings
"""
function get_tool_results(agent::FluidAgent, max_length::Int=20000; filter_tools::Vector{DataType}=Datasources[])
    ctx = get_tool_results(agent.extractor; filter_tools)
    if length(ctx) > max_length
        @warn "Shell context too long, truncating to $max_length characters"
        return ctx, ctx[1:min(max_length, end)]
    end
    return ctx, ctx
end
"""
Process and execute tools in order while allowing parallel preprocessing
"""
function process_tools!(content::String, agent::FluidAgent; no_confirm=false)
    tags = parse_tools(content)
    isempty(tags) && return OrderedDict{UUID,String}()
    
    # Convert tags to tools and execute
    tools = OrderedDict{UUID,AbstractTool}()
    for tag in tags
        tool = create_tool(agent, tag)
        tools[tool.id] = tool
    end
    
    # Execute tools and collect results
    execute_tools(tools; no_confirm)
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
Run an LLM interaction with tool execution.

Returns a NamedTuple with:
- content: The AI response content 
- run_info: Callback run information
- extractor: Tool tag extractor with execution results

Note: Stop sequences from tools are collected and passed to the LLM to prevent 
generating beyond tool boundaries.
"""
function work(agent::FluidAgent, conv; cache,
    no_confirm=false,
    highlight_enabled::Bool=true,
    process_enabled::Bool=true,
    on_error=noop,
    on_done=noop,
    on_start=noop,
    io=stdout,
    tool_kwargs=Dict())
    
    # Create new ToolTagExtractor for each run
    extractor = ToolTagExtractor()
    agent.extractor = extractor
    
    # Collect unique stop sequences from tools
    stop_sequences = unique(String[stop_sequence(tool) for tool in agent.tools if has_stop_sequence(tool)])
    
    if length(stop_sequences) > 1
        @warn "Multiple different stop sequences detected: $(join(stop_sequences, ", "))"
    end
    
    # Base API kwargs without stop sequences
    api_kwargs = (; top_p=0.7, temperature=0.5, max_tokens=8192)
    
    if agent.model == "o3m" # NOTE: o3m does not support temperature and top_p
        api_kwargs = (; )
    end

    apply_stop_seq_kwargs!(api_kwargs, agent.model, stop_sequences)
    StreamCallbackTYPE= pickStreamCallbackforIO(io)
    cb = create(StreamCallbackTYPE(; io, on_start, on_error, highlight_enabled, process_enabled,
        on_done = () -> begin
            process_enabled && extract_tool_calls("\n", extractor; kwargs=tool_kwargs, is_flush=true)
            on_done()
        end,
        on_content = process_enabled ? (text -> extract_tool_calls(text, extractor; kwargs=tool_kwargs)) : noop,
    ))
    
    try
        response = aigenerate(
            to_PT_messages(conv);
            model=agent.model,
            cache, 
            api_kwargs,
            streamcallback=cb,
            verbose=false
        )
        execute_tools(extractor; no_confirm)
        
        # Return named tuple with all needed components
        return (;
            content = response.content,
            run_info = cb.run_info,
            extractor,
        )
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))" exception=(e, catch_backtrace())
        on_error(e)
        return (
            content = "Error: $(sprint(showerror, e))\n\nPartial response: $(extractor.full_content)",
            results = OrderedDict{UUID,String}(),
            run_info = cb.run_info,
        )
    end
    # TODO this while loop should somehow work in this work thing:

    # while true
    #       work
    #     # (isnothing(cb.run_info.stop_sequence) || isempty(flow.extractor.tool_tasks)) && break
    #     # result = get_last_command_result(flow.extractor)
    #     # isnothing(result) && continue
    #     # print_tool_result(result)
    #     # flow.conv_ctx(create_user_message(truncate_output(result), Dict("context" => result)))
        
    #     # !isnothing(result) && write_event!(io, "command_result", result)
    # end
end
"""
Apply stop sequence kwargs based on model type and available sequences.
"""
function apply_stop_seq_kwargs!(api_kwargs::NamedTuple, model::String, stop_sequences::Vector{String})
    isempty(stop_sequences) && return api_kwargs
    key = model == "claude" ? :stop_sequences : :stop
    merge(api_kwargs, (; key => stop_sequences))
end