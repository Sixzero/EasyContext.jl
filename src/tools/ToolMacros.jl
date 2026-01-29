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

export @tool, @tool_passive

using ToolCallFormat: ToolSchema, ParamSchema, generate_tool_definition, CallStyle, get_default_call_style
using UUIDs: UUID, uuid4

# Valid schema types (from ToolCallFormat)
const VALID_SCHEMA_TYPES = Set(["string", "codeblock", "number", "integer", "boolean", "array", "object"])

#==============================================================================#
# @tool_passive - Minimal tool (no params, no execute)
#==============================================================================#

"""
    @tool_passive StructName "tool_name"

Create a passive tool with just id + content. No parameters, no execute.

Example:
    @tool_passive ReasonTool "ReasonTool"
"""
macro tool_passive(struct_name, tool_name)
    sn = esc(struct_name)
    quote
        @kwdef mutable struct $sn <: AbstractTool
            id::UUID = uuid4()
            content::String = ""
        end
        EasyContext.toolname(::Type{$sn}) = $tool_name
        EasyContext.toolname(::$sn) = $tool_name
        EasyContext.execute_required_tools(::$sn) = false
    end
end

#==============================================================================#
# @tool - Full tool definition
#==============================================================================#

"""
    @tool StructName "tool_name" "description" params [execute_fn] [result_fn]

Define a tool with schema. The params define both struct fields AND the AI schema.

params: Vector of (name, type, description, required, default)
  - type: "string", "codeblock", "number", "integer", "boolean", "array", "object"

Example:
    @tool CatFileTool "cat_file" "Read file contents" [
        (:path, "string", "File path", true, nothing),
        (:limit, "integer", "Max lines", false, nothing),
    ] (tool; kw...) -> read(tool.path)

Note: execute_fn and result_fn are positional. To provide result_fn without execute_fn,
pass `nothing` for execute_fn:
    @tool MyTool "name" "desc" params nothing my_result_fn

CallStyle Support:
    get_description(MyTool)                    # Uses default style
    get_description(MyTool, PYTHON)            # Uses Python style
    get_description(MyTool, CONCISE)           # Uses concise style
"""
macro tool(struct_name, tool_name, description, params_expr, execute_expr=nothing, result_expr=nothing)
    # Parse params from AST
    params = _parse_params_ast(params_expr)

    # Validate all params
    for (i, param) in enumerate(params)
        _validate_param(param, i)
    end

    # Base fields that every tool has
    base_fields = [
        (:id, UUID, :(uuid4())),
        (:content, String, :("")),
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

    sn = esc(struct_name)

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
