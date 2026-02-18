# NativeExtractor - Minimal native API tool_call extractor for standalone EasyContext
#
# Unlike TODO4AI's NativeCallExtractor:
# - No block protocol (no start_block!/end_block!/AbstractIOWrapper)
# - No permission system (uses no_confirm kwarg + LLM_safetorun)
# - Works with plain IO (stdout)

using DataStructures: OrderedDict
using UUIDs: UUID, uuid4
using OpenRouter: ToolMessage

export NativeExtractor, SimpleContext

"""Minimal context for standalone tool execution. Carries kwargs as fields accessible via getproperty."""
struct SimpleContext <: ToolCallFormat.AbstractContext
    kwargs::Dict{Symbol, Any}
end
SimpleContext(; kwargs...) = SimpleContext(Dict{Symbol, Any}(kwargs...))
Base.getproperty(ctx::SimpleContext, name::Symbol) = name == :kwargs ? getfield(ctx, :kwargs) : get(getfield(ctx, :kwargs), name, nothing)
Base.get(ctx::SimpleContext, key::Symbol, default) = get(getfield(ctx, :kwargs), key, default)
Base.hasproperty(ctx::SimpleContext, name::Symbol) = name == :kwargs || haskey(getfield(ctx, :kwargs), name)

@kwdef mutable struct NativeExtractor <: AbstractExtractor
    tools::Vector = DataType[]
    tool_names::Set{String} = Set{String}()
    tool_map::Dict{String, Any} = Dict{String, Any}()
    tool_tasks::OrderedDict{UUID, Task} = OrderedDict{UUID, Task}()
    block_to_call_id::Dict{UUID, String} = Dict{UUID, String}()
    has_pending_approvals::Bool = false
    no_confirm::Bool = false
    full_content::String = ""  # accumulates streamed text for interrupted save
end

function NativeExtractor(tools::Vector; no_confirm::Bool=false)
    tool_names = Set{String}()
    tool_map = Dict{String, Any}()
    for tool in tools
        name = ToolCallFormat.toolname(tool)
        !isempty(name) && (push!(tool_names, name); tool_map[name] = tool)
    end
    NativeExtractor(; tools, tool_names, tool_map, no_confirm)
end

# Native mode: no parsing needed, just accumulate text for interrupted save
function EasyContext.extract_tool_calls(text::String, extractor::NativeExtractor, io; kwargs...)
    extractor.full_content *= text
    return nothing
end

function EasyContext.process_native_tool_calls!(extractor::NativeExtractor, tool_calls::Vector, io; kwargs=Dict())
    no_confirm = extractor.no_confirm || get(kwargs, :no_confirm, false)
    ctx = get(kwargs, :ctx, SimpleContext())

    for tc in tool_calls
        call = tool_call_to_parsed_call(tc)
        api_call_id = tc["id"]

        # Inject kwargs into ParsedCall for struct field population (root_path, no_confirm, etc.)
        no_confirm && !haskey(call.kwargs, "no_confirm") && (call.kwargs["no_confirm"] = ToolCallFormat.ParsedValue(value=no_confirm, raw="true"))
        for (k, v) in kwargs
            k in (:no_confirm, :ctx) && continue
            !haskey(call.kwargs, string(k)) && (call.kwargs[string(k)] = ToolCallFormat.ParsedValue(value=v, raw=string(v)))
        end

        if !haskey(extractor.tool_map, call.name)
            @warn "Native tool_call not found" tool_name=call.name
            continue
        end

        tool_entry = extractor.tool_map[call.name]
        tool = ToolCallFormat.create_tool(tool_entry, call)
        block_id = ToolCallFormat.get_id(tool)
        extractor.block_to_call_id[block_id] = api_call_id

        # Check safety: no_confirm bypasses, otherwise use LLM_safetorun
        safe = no_confirm || LLM_safetorun(tool)
        if !safe
            extractor.has_pending_approvals = true
            extractor.tool_tasks[block_id] = @async nothing
            continue
        end

        extractor.tool_tasks[block_id] = @async begin
            is_executable(tool) || return nothing
            ToolCallFormat.execute(tool, ctx)
            tool
        end
    end
end

function EasyContext.any_tool_needs_approval(extractor::NativeExtractor)
    extractor.has_pending_approvals
end

function EasyContext.collect_tool_messages(extractor::NativeExtractor; timeout::Float64=300.0)::Vector{ToolMessage}
    tool_entries = collect(extractor.tool_tasks)

    async_results = [@async begin
        call_id = get(extractor.block_to_call_id, block_id, nothing)
        if isnothing(call_id)
            @error "No tool_call_id mapping for block_id — ToolMessage will have wrong call_id" block_id
            call_id = string(block_id)
        end
        result = timedwait(timeout; pollint=0.5) do; istaskdone(task) end
        if result == :timed_out
            @warn "Tool timed out after $(timeout)s"
            schedule(task, InterruptException(); error=true)
            return ToolMessage(content="[timeout]", tool_call_id=call_id)
        end

        tool = try fetch(task) catch e
            return ToolMessage(content="Error: $(sprint(showerror, e))", tool_call_id=call_id)
        end

        if isnothing(tool)
            return ToolMessage(content="(no result)", tool_call_id=call_id)
        end

        content = result2string(tool)
        content = isnothing(content) || isempty(content) ? "(completed)" : content
        img = resultimg2base64(tool)
        image_data = (isnothing(img) || isempty(img)) ? nothing : [img]
        ToolMessage(; content, tool_call_id=call_id, image_data)
    end for (block_id, task) in tool_entries]

    [fetch(t) for t in async_results]
end
