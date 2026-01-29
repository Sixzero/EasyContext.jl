# ToolMacros.jl - Macros for defining tools with minimal boilerplate
#
# Parameter types (these tell the AI how to format):
#   "string"    - Single line text
#   "codeblock" - Multi-line code block
#   "number"    - Numeric value
#   "integer"   - Integer value
#   "boolean"   - Boolean value
#   "array"     - JSON array
#   "object"    - JSON object
#
# Uses ToolCallFormat for schema types and generation.
# Supports CallStyles for different output formats (CONCISE, PYTHON, MINIMAL, TYPESCRIPT).

export @tool

using ToolCallFormat: ToolSchema, ParamSchema, generate_tool_definition, CallStyle, get_default_call_style
using ToolCallFormat: ParsedCall, ParsedValue
using UUIDs: UUID, uuid4

# Valid schema types (from ToolCallFormat)
const VALID_SCHEMA_TYPES = Set(["string", "codeblock", "number", "integer", "boolean", "array", "object"])

# Reserved field names (used by base struct fields)
# - id: unique tool instance identifier (UUID)
# - result: stores execution output
# - auto_run: permission flag for auto-execution
const RESERVED_FIELD_NAMES = Set([:id, :result, :auto_run])

const RESERVED_FIELD_DESCRIPTIONS = Dict(
    :id => "unique tool instance identifier (UUID)",
    :result => "stores execution output",
    :auto_run => "permission flag for auto-execution"
)

#==============================================================================#
# @tool - Unified tool definition macro
#==============================================================================#

"""
    @tool StructName "tool_name" "description" [params] [execute_fn] [result_fn]

Define a tool with optional schema and execution.

## Passive mode (no params or empty params):
    @tool ReasonTool "ReasonTool" "Store reasoning"
    @tool ReasonTool "ReasonTool" "Store reasoning" []

Creates: struct with id + content fields only.

## Active mode (with params):
    @tool CatFileTool "cat_file" "Read file contents" [
        (:path, "string", "File path", true, nothing),
        (:limit, "integer", "Max lines", false, nothing),
    ] (tool; kw...) -> read(tool.path)

Creates: struct with id + result + auto_run + user params.

params: Vector of (name, type, description, required, default)
  - type: "string", "codeblock", "number", "integer", "boolean", "array", "object"

Note: execute_fn and result_fn are positional. To provide result_fn without execute_fn,
pass `nothing` for execute_fn:
    @tool MyTool "name" "desc" params nothing my_result_fn

CallStyle Support:
    get_description(MyTool)                    # Uses default style
    get_description(MyTool, PYTHON)            # Uses Python style
    get_description(MyTool, CONCISE)           # Uses concise style
"""
macro tool(struct_name, tool_name, description, params_expr=:([]), execute_expr=nothing, result_expr=nothing)
    # Parse params from AST
    params = _parse_params_ast(params_expr)

    # Validate all params
    for (i, param) in enumerate(params)
        _validate_param(param, i)
    end

    sn = esc(struct_name)
    is_passive = isempty(params)

    if is_passive
        # PASSIVE MODE: just id + content, no execute, no result
        result = quote
            @kwdef mutable struct $sn <: AbstractTool
                id::UUID = uuid4()
                content::String = ""
            end

            EasyContext.toolname(::Type{$sn}) = $tool_name
            EasyContext.toolname(::$sn) = $tool_name

            # Passive tools: simple description
            function EasyContext.get_description(::Type{$sn}, style::CallStyle=get_default_call_style())
                generate_tool_definition(ToolSchema(
                    name=$tool_name,
                    description=$description,
                    params=ParamSchema[]
                ); style=style)
            end
            EasyContext.get_description(t::$sn, style::CallStyle=get_default_call_style()) = EasyContext.get_description(typeof(t), style)

            EasyContext.get_tool_schema(::Type{$sn}) = (name = $tool_name, description = $description, params = [])

            EasyContext.execute_required_tools(::$sn) = false
            EasyContext.is_cancelled(::$sn) = false

            # create_tool for ParsedCall (primary method)
            EasyContext.create_tool(::Type{$sn}, call::ParsedCall) = $sn(content=call.content)
        end
    else
        # ACTIVE MODE: id + result + auto_run + user params

        # Base fields (no content - users can add their own content param)
        base_fields = [
            (:id, UUID, :(uuid4())),
            (:result, String, :("")),
            (:auto_run, Bool, :(false)),
        ]

        # User-defined fields from params
        user_fields = [
            begin
                jl_type = _schema_to_julia_type(type_str)
                def_expr = default === nothing ? _default_value_expr(jl_type) : default
                (name, jl_type, def_expr)
            end
            for (name, type_str, _, _, default) in params
        ]

        all_fields = vcat(base_fields, user_fields)

        # Generate struct field declarations
        struct_field_exprs = [:($name::$jl_type) for (name, jl_type, _) in all_fields]

        # Generate keyword constructor arguments
        kwarg_exprs = [Expr(:kw, name, def_expr) for (name, _, def_expr) in all_fields]

        # Generate constructor call arguments
        call_arg_exprs = [name for (name, _, _) in all_fields]

        # Generate schema params
        schema_exprs = [
            :(ParamSchema(name=$(string(name)), type=$type_str, description=$desc, required=$req))
            for (name, type_str, desc, req, _) in params
        ]

        result = quote
            # Define the struct
            mutable struct $sn <: AbstractTool
                $(struct_field_exprs...)
            end

            # Keyword constructor
            function $sn(; $(kwarg_exprs...))
                $sn($(call_arg_exprs...))
            end

            EasyContext.toolname(::Type{$sn}) = $tool_name
            EasyContext.toolname(::$sn) = $tool_name

            # get_description with optional CallStyle
            function EasyContext.get_description(::Type{$sn}, style::CallStyle=get_default_call_style())
                generate_tool_definition(ToolSchema(
                    name=$tool_name,
                    description=$description,
                    params=ParamSchema[$(schema_exprs...)]
                ); style=style)
            end
            EasyContext.get_description(t::$sn, style::CallStyle=get_default_call_style()) = EasyContext.get_description(typeof(t), style)

            # get_tool_schema returns the schema for programmatic access
            function EasyContext.get_tool_schema(::Type{$sn})
                (
                    name = $tool_name,
                    description = $description,
                    params = [
                        $([:(( name = $(string(name)), type = $type_str, description = $desc, required = $req ))
                          for (name, type_str, desc, req, _) in params]...)
                    ]
                )
            end

            EasyContext.execute_required_tools(tool::$sn) = tool.auto_run
            EasyContext.is_cancelled(::$sn) = false
        end

        # Generate create_tool for ParsedCall (primary method)
        _add_create_tool_parsedcall!(result, sn, params)

        # Add execute if provided
        if execute_expr !== nothing
            push!(result.args, :(
                EasyContext.execute(tool::$sn; no_confirm=false, kwargs...) =
                    $(esc(execute_expr))(tool; no_confirm, kwargs...)
            ))
        end

        # Add result2string
        if result_expr !== nothing
            push!(result.args, :(
                EasyContext.result2string(tool::$sn)::String = $(esc(result_expr))(tool)
            ))
        else
            push!(result.args, :(
                EasyContext.result2string(tool::$sn)::String = tool.result
            ))
        end
    end

    result
end

#==============================================================================#
# AST Parsing (internal)
#==============================================================================#

"""Parse the params array from AST without using eval."""
function _parse_params_ast(expr)
    if !(expr isa Expr && expr.head == :vect)
        error("@tool params must be a literal array [...], got: $(typeof(expr))")
    end
    return [_parse_single_param(arg) for arg in expr.args]
end

"""Parse a single param tuple from AST."""
function _parse_single_param(expr)
    if !(expr isa Expr && expr.head == :tuple)
        error("Each param must be a tuple (name, type, desc, required, default), got: $expr")
    end

    args = expr.args
    if length(args) != 5
        error("Param tuple must have exactly 5 elements, got $(length(args)): $expr")
    end

    # Parse name
    name = if args[1] isa QuoteNode
        args[1].value
    elseif args[1] isa Symbol
        args[1]
    else
        error("Param name must be a symbol like :path, got: $(args[1])")
    end

    # Parse type string
    type_str = args[2]
    type_str isa String || error("Param type must be a string, got: $(type_str)")

    # Parse description
    desc = args[3]
    desc isa String || error("Param description must be a string, got: $(desc)")

    # Parse required
    req = args[4]
    req isa Bool || error("Param required must be true or false, got: $(req)")

    # Parse default (handle `nothing` literal as Symbol :nothing in AST)
    default = args[5]
    if default isa Symbol && default == :nothing
        default = nothing
    end

    return (name, type_str, desc, req, default)
end

#==============================================================================#
# Validation (internal)
#==============================================================================#

"""Validate a parsed param tuple."""
function _validate_param(param, index::Int)
    name, type_str, desc, req, default = param

    name isa Symbol || error("Param $index: name must be a Symbol, got $(typeof(name))")

    # Check for reserved field names
    if name in RESERVED_FIELD_NAMES
        desc_str = RESERVED_FIELD_DESCRIPTIONS[name]
        reserved_list = join(["  :$k - $(RESERVED_FIELD_DESCRIPTIONS[k])" for k in sort(collect(RESERVED_FIELD_NAMES))], "\n")
        error("""Param $index: name :$name is reserved (used for: $desc_str).
Choose a different name.

Reserved field names:
$reserved_list""")
    end

    if !(type_str in VALID_SCHEMA_TYPES)
        error("Param $index (:$name): invalid type \"$type_str\". Valid: $(join(sort(collect(VALID_SCHEMA_TYPES)), ", "))")
    end

    isempty(desc) && @warn "Param $index (:$name): description is empty"
end

#==============================================================================#
# Type Mapping (internal)
#==============================================================================#

"""Map schema type strings to Julia types."""
function _schema_to_julia_type(type_str::String)
    type_str == "string" || type_str == "codeblock" ? String :
    type_str == "number" ? Union{Float64,Nothing} :
    type_str == "integer" ? Union{Int,Nothing} :
    type_str == "boolean" ? Bool :
    type_str == "array" ? Vector{Any} :
    type_str == "object" ? Dict{String,Any} :
    error("Unknown schema type: \"$type_str\"")
end

"""Return quoted expression for default value of a Julia type."""
function _default_value_expr(T::Type)
    T == String ? :("") :
    T == Bool ? :(false) :
    T == Vector{Any} ? :(Any[]) :
    T == Dict{String,Any} ? :(Dict{String,Any}()) :
    :(nothing)
end

#==============================================================================#
# create_tool generation (internal)
#==============================================================================#

"""
Generate create_tool(::Type{T}, tag::ToolTag) method.

Strategy:
- First required string param → tag.args
- Codeblock param → tag.content
- Other params → tag.kwargs with type conversion
"""
function _add_create_tool_tooltag!(result, sn, params)
    # Find first required string param (will use tag.args)
    first_string_idx = findfirst(p -> p[2] == "string" && p[4], params)

    # Build keyword arguments for constructor
    kwarg_assignments = Expr[]

    for (i, (name, type_str, _, required, default)) in enumerate(params)
        name_str = string(name)
        name_sym = name

        value_expr = if type_str == "codeblock"
            # Codeblock always comes from tag.content
            :(tag.content)
        elseif i == first_string_idx
            # First required string param comes from tag.args
            :(tag.args)
        else
            # Other params come from tag.kwargs with conversion
            default_val = default === nothing ? _default_value_for_type(type_str) : default
            _kwargs_access_expr(name_str, type_str, default_val)
        end

        push!(kwarg_assignments, Expr(:kw, name_sym, value_expr))
    end

    push!(result.args, :(
        function EasyContext.create_tool(::Type{$sn}, tag::ToolTag)
            $sn(; $(kwarg_assignments...))
        end
    ))
end

"""
Generate create_tool(::Type{T}, call::ParsedCall) method.

Strategy:
- All params from call.kwargs as ParsedValue
- Codeblock also checks call.content if kwargs empty
"""
function _add_create_tool_parsedcall!(result, sn, params)
    kwarg_assignments = Expr[]

    for (name, type_str, _, required, default) in params
        name_str = string(name)
        name_sym = name

        default_val = default === nothing ? _default_value_for_type(type_str) : default

        value_expr = if type_str == "codeblock"
            # Codeblock: prefer kwargs, fallback to call.content
            :(let v = get(call.kwargs, $name_str, nothing)
                v !== nothing ? v.value : (isempty(call.content) ? $default_val : call.content)
            end)
        else
            # Regular param from kwargs
            _parsedcall_access_expr(name_str, type_str, default_val)
        end

        push!(kwarg_assignments, Expr(:kw, name_sym, value_expr))
    end

    push!(result.args, :(
        function EasyContext.create_tool(::Type{$sn}, call::ParsedCall)
            $sn(; $(kwarg_assignments...))
        end
    ))
end

"""Generate expression to access tag.kwargs with type conversion."""
function _kwargs_access_expr(name::String, type_str::String, default)
    base_expr = :(get(tag.kwargs, $name, nothing))

    if type_str == "string"
        :(let v = $base_expr; v === nothing ? $default : String(v) end)
    elseif type_str == "integer"
        :(let v = $base_expr; v === nothing ? $default : parse(Int, v) end)
    elseif type_str == "number"
        :(let v = $base_expr; v === nothing ? $default : parse(Float64, v) end)
    elseif type_str == "boolean"
        :(let v = $base_expr; v === nothing ? $default : lowercase(v) in ("true", "1", "yes") end)
    else
        # array, object - return as-is or default
        :(let v = $base_expr; v === nothing ? $default : v end)
    end
end

"""Generate expression to access call.kwargs (ParsedValue) with type extraction."""
function _parsedcall_access_expr(name::String, type_str::String, default)
    # ParsedCall kwargs are Dict{String, ParsedValue}, need to extract .value
    :(let pv = get(call.kwargs, $name, nothing)
        pv === nothing ? $default : pv.value
    end)
end

"""Return a literal default value for a type string."""
function _default_value_for_type(type_str::String)
    type_str == "string" || type_str == "codeblock" ? "" :
    type_str == "boolean" ? false :
    type_str == "array" ? Any[] :
    type_str == "object" ? Dict{String,Any}() :
    nothing  # integer, number default to nothing
end
