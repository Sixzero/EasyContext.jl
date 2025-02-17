using UUIDs
using PromptingTools
using PromptingTools: aigenerate
using StreamCallbacksExt: needs_tool_execution

export FluidAgent, execute_tools, work

"""
FluidAgent manages a set of tools and executes them using LLM guidance.
"""
@kwdef mutable struct FluidAgent
    tools::Vector{Type{<:AbstractTool}} 
    model::String = "claude"
    workspace::String = pwd()
    tool_map::Dict{String,Type{<:AbstractTool}} = Dict(toolname(T) => T for T in tools)
    extractor::ToolTagExtractor = ToolTagExtractor()
    sys_msg::String = ""
end 
# create_FluidAgent to prevent conflict with the constructor
function create_FluidAgent(model::String="claude"; create_sys_msg::Function, tools::Vector{T}) where T
    sys_msg = """
    $(create_sys_msg())

    $(highlight_code_guide)
    $(highlight_changes_guide)
    $(organize_file_guide)
    $(shell_script_n_result_guide_v2)

    $(dont_act_chaotic)
    $(refactor_all)
    $(simplicity_guide)
    
    $(ambiguity_guide)
    
    $(test_it_v2)
    
    $(no_loggers)
    $(julia_specific_guide)
    $(system_information)

    $(get_tool_descriptions(tools))

    If a tool doesn't return results after asking for results with #RUN then don't rerun it, but write, we didn't receive results from the specific tool usage.

    Follow KISS and SOLID principles.

    $(conversaton_starts_here)"""
    agent = FluidAgent(; sys_msg, tools=convert_tool_types(tools), model)
    agent
end

get_tool_descriptions(agent::FluidAgent) = get_tool_descriptions(agent.tools)
"""
Get tool descriptions for system prompt
"""
function get_tool_descriptions(tools::AbstractVector)
    descriptions = get_description.(tools)
    """
    # Available tools:
    $(join(descriptions, "\n\n"))"""
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
function get_tool_results_agent(agent::FluidAgent, max_length::Int=20000; filter_tools::Vector{DataType}=DataType[])
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
"""
function work(agent::FluidAgent, conv; cache,
    no_confirm=false,
    highlight_enabled::Bool=true,
    process_enabled::Bool=true,
    on_error=noop,
    on_done=noop,
    on_start=noop,
    io=stdout,
    extractor_type=ToolTagExtractor,
    tool_kwargs=Dict()
    )
    
    
    # Collect unique stop sequences from tools
    stop_sequences = unique(String[stop_sequence(tool) for tool in agent.tools if has_stop_sequence(tool)])
    
    if length(stop_sequences) > 1
        @warn "Untested: Multiple different stop sequences detected: $(join(stop_sequences, ", "))"
    end
    
    # Base API kwargs without stop sequences
    api_kwargs = (; top_p=0.7, temperature=0.5, max_tokens=8192)
    
    if agent.model == "o3m" # NOTE: o3m does not support temperature and top_p
        api_kwargs = (; )
    end

    api_kwargs = apply_stop_seq_kwargs(api_kwargs, agent.model, stop_sequences)
    StreamCallbackTYPE= pickStreamCallbackforIO(io)

    try

        response = nothing
        while true
            # Create new ToolTagExtractor for each run
            extractor = extractor_type(agent.tools)
            agent.extractor = extractor

            cb = create(StreamCallbackTYPE(; io, on_start, on_error, highlight_enabled, process_enabled,
                on_done = () -> begin
                    # Extracts tools in case anything is unclosed
                    process_enabled && extract_tool_calls("\n", extractor, io; kwargs=tool_kwargs, is_flush=true)
                    on_done()
                end,
                on_content = process_enabled ? (text -> extract_tool_calls(text, extractor, io; kwargs=tool_kwargs)) : noop,
            ))

            response = aigenerate(
                to_PT_messages(conv, agent.sys_msg);
                model=agent.model,
                cache, 
                api_kwargs,
                streamcallback=cb,
                verbose=false
            )

            execute_tools(extractor; no_confirm)
            # Break if no more tool execution needed
            !needs_tool_execution(cb.run_info) && break
            length(extractor.tool_tags) == 0 && break
            
            # Add tool results to conversation for next iteration
            result, _ = get_tool_results_agent(agent)
            push_message!(conv, create_user_message(result))
            sleep(1)
        end

        push_message!(conv, create_AI_message(response.content))
        
        return response
    catch e
        e isa InterruptException && rethrow(e)
        @error "Error executing code block: $(sprint(showerror, e))"
        on_error(e)
        content = "Error: $(sprint(showerror, e))\n\nStacktrace: $(sprint(show, stacktrace))"
        push_message!(conv, create_AI_message(content))
        return (; 
            content,
            results = OrderedDict{UUID,String}(),
            run_info = nothing,
        )
    end
end

"""
Apply stop sequence kwargs based on model type and available sequences.
"""
function apply_stop_seq_kwargs(api_kwargs::NamedTuple, model::String, stop_sequences::Vector{String})
    isempty(stop_sequences) && return api_kwargs
    key = model == "claude" ? :stop_sequences : :stop
    merge(api_kwargs, (; key => stop_sequences))
end