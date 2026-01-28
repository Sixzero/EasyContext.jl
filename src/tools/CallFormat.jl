# CallFormat - Tool description format system
# Provides consistent tool description generation for LLM prompts

export CallStyle, CONCISE, PYTHON, MINIMAL, TYPESCRIPT
export ToolFormatConfig, CallFormatConfig
export ParamSchema, ToolSchema
export generate_tool_definition, generate_tool_definitions
export generate_format_documentation, generate_system_prompt
export get_default_call_style, set_default_call_style!
export simple_tool_schema, code_tool_schema
export short_type, python_type

"""
Call format styles for function-call syntax.
Each style uses different syntax conventions familiar to different programming communities.
"""
@enum CallStyle begin
    CONCISE      # Default - upgraded TypeScript with positional + named args (key: value)
    PYTHON       # Python-like with = for named args (key=value)
    MINIMAL      # Clean with # comments (key: value)
    TYPESCRIPT   # Strict TS compat (key: value)
end

# Global default style (can be changed at runtime)
const DEFAULT_CALL_STYLE = Ref{CallStyle}(CONCISE)

"""
Get the default CallStyle.
"""
get_default_call_style()::CallStyle = DEFAULT_CALL_STYLE[]

"""
Set the default CallStyle.
"""
function set_default_call_style!(style::CallStyle)
    DEFAULT_CALL_STYLE[] = style
end

"""
Configuration for tool format.
Style determines the syntax style for function-call format.
"""
@kwdef struct ToolFormatConfig
    style::CallStyle = CONCISE
end

# Convenience constructor
CallFormatConfig(style::CallStyle=CONCISE) = ToolFormatConfig(style=style)

"""
Parameter schema for a single tool parameter.
Used when generating tool definitions for system prompts.
"""
@kwdef struct ParamSchema
    name::String
    type::String           # "string", "number", "boolean", "null", "string[]", "object", "codeblock"
    description::String = ""
    required::Bool = true
end

"""
Tool schema representing a complete tool definition.
Used when generating tool definitions for system prompts.
"""
@kwdef struct ToolSchema
    name::String
    params::Vector{ParamSchema} = ParamSchema[]
    description::String = ""
end

# ============================================================================
# Format Documentation (teaches LLM how to make tool calls)
# ============================================================================

"""
Generate the tool call format documentation for system prompts.
This teaches the LLM how to make tool calls in the specified format style.
"""
function generate_format_documentation(style::CallStyle=get_default_call_style())::String
    if style == PYTHON
        return generate_python_format_docs()
    elseif style == MINIMAL
        return generate_minimal_format_docs()
    elseif style == TYPESCRIPT
        return generate_typescript_format_docs()
    else
        return generate_concise_format_docs()
    end
end

function generate_concise_format_docs()::String
    """
## Tool Call Format

```
tool_name(value)
tool_name(param: value)
```

**Rules:**
- Tool call must start at the **beginning of a line**
- Tool call must end with `)` followed by **newline**
- Positional args first, then named args with `:`

**Types:** `str`, `int`, `bool`, `null`, `list`, `obj`, `codeblock`

**Examples:**
```
read_file("/file.txt")

edit("/test.txt", old: "hello", new: "goodbye")

bash(```echo "hello"```)

bash(
  ```bash
  npm install
  ```
  timeout: 60000
)
```
"""
end

function generate_typescript_format_docs()::String
    """
## Tool Call Format

```
tool_name(param: value, param2: value2)
```

**Rules:**
- Tool call must start at the **beginning of a line**
- Tool call must end with `)` followed by **newline** or **code block**

**Types:** `string` ("text"), `number` (42, 3.14), `boolean` (true/false), `null`, `string[]` (["a","b"]), `object` ({k: v}), `codeblock` (``` fenced block ```)

**Examples:**
```
read_file(path: "/file.txt", limit: 100)

edit(file_path: "/test.txt", old_string: "hello", new_string: "goodbye")

shell(lang: "sh") ```
ls -la
```
```

**With codeblock:** For multiline content, use a fenced code block:
```
tool_name(param: "value") ```
multiline content here
```
```
"""
end

function generate_python_format_docs()::String
    """
## Tool Call Format

```
tool_name(param=value, param2=value2)
```

**Rules:**
- Tool call must start at the **beginning of a line**
- Tool call must end with `)` followed by **newline**
- Use `=` for named arguments, positional arguments don't need names

**Types:** `str` ("text"), `int`/`float` (42, 3.14), `bool` (True/False), `None`, `list` (["a","b"]), `dict` ({k: v}), `codeblock` (``` fenced block ```)

**Examples:**
```
read_file("/file.txt", limit=100)

edit(file_path="/test.txt", old_string="hello", new_string="goodbye")

bash(```
ls -la
echo "hello"
```)

bash(```bash
npm install
```, timeout=60000)
```
"""
end

function generate_minimal_format_docs()::String
    """
## Tool Call Format

```
tool_name(param: value, param2: value2)
```

**Rules:**
- Tool call must start at the **beginning of a line**
- Tool call must end with `)` followed by **newline**
- Use `:` for named arguments, positional arguments are allowed

**Types:** `string`, `int`, `bool` (true/false), `null`, `string[]`, `object`, `codeblock`

**Examples:**
```
read_file("/file.txt", limit: 100)

edit(file_path: "/test.txt", old_string: "hello", new_string: "goodbye")

bash(
    ```bash
    ls -la
    echo "hello"
    ```
    timeout: 60000
)
```
"""
end

# ============================================================================
# Tool Definition Generation
# ============================================================================

"""
Generate a single tool definition in the specified style.
If no style is provided, uses the default style.
"""
function generate_tool_definition(schema::ToolSchema; style::CallStyle=get_default_call_style())::String
    if style == PYTHON
        return generate_tool_definition_python(schema)
    elseif style == MINIMAL
        return generate_tool_definition_minimal(schema)
    elseif style == TYPESCRIPT
        return generate_tool_definition_typescript(schema)
    else
        return generate_tool_definition_concise(schema)
    end
end

"""
Generate tool definition in Concise style (default).
"""
function generate_tool_definition_concise(schema::ToolSchema)::String
    io = IOBuffer()

    write(io, "### `$(schema.name)`\n\n")

    if !isempty(schema.description)
        write(io, "```\n/// $(schema.description)\n")
    else
        write(io, "```\n")
    end

    write(io, "$(schema.name)(")

    if !isempty(schema.params)
        if length(schema.params) <= 2
            param_strs = String[]
            for param in schema.params
                opt = param.required ? "" : "?"
                t = short_type(param.type)
                push!(param_strs, "$(param.name)$(opt): $(t)")
            end
            write(io, join(param_strs, ", "))
            write(io, ")\n```\n\n")
        else
            write(io, "\n")
            for param in schema.params
                opt = param.required ? "" : "?"
                t = short_type(param.type)
                desc = isempty(param.description) ? "" : " # $(param.description)"
                write(io, "  $(param.name)$(opt): $(t)$(desc)\n")
            end
            write(io, ")\n```\n\n")
        end
    else
        write(io, ")\n```\n\n")
    end

    return String(take!(io))
end

"""
Generate tool definition in TypeScript style.
"""
function generate_tool_definition_typescript(schema::ToolSchema)::String
    io = IOBuffer()

    write(io, "### `$(schema.name)`\n\n")

    if !isempty(schema.description)
        write(io, "$(schema.description)\n\n")
    end

    if !isempty(schema.params)
        write(io, "```typescript\n$(schema.name)(")

        param_strs = String[]
        for param in schema.params
            opt = param.required ? "" : "?"
            push!(param_strs, "$(param.name)$(opt): $(param.type)")
        end

        if length(param_strs) <= 2
            write(io, join(param_strs, ", "))
        else
            write(io, "\n")
            for (i, ps) in enumerate(param_strs)
                write(io, "    $ps")
                if i < length(param_strs)
                    write(io, ",")
                end
                write(io, "\n")
            end
        end

        write(io, ")\n```\n\n")

        write(io, "Parameters:\n")
        for param in schema.params
            opt_marker = param.required ? "" : " *(optional)*"
            write(io, "- `$(param.name)` ($(param.type))$(opt_marker)")
            if !isempty(param.description)
                write(io, ": $(param.description)")
            end
            write(io, "\n")
        end
    else
        write(io, "```typescript\n$(schema.name)()\n```\n\n")
        write(io, "No parameters.\n")
    end

    return String(take!(io))
end

"""
Generate tool definition in Python style.
"""
function generate_tool_definition_python(schema::ToolSchema)::String
    io = IOBuffer()

    write(io, "### `$(schema.name)`\n\n")

    write(io, "```python\ndef $(schema.name)(")

    if !isempty(schema.params)
        param_strs = String[]
        for param in schema.params
            type_hint = python_type(param.type)
            if param.required
                push!(param_strs, "$(param.name): $(type_hint)")
            else
                push!(param_strs, "$(param.name): $(type_hint) | None = None")
            end
        end

        if length(param_strs) <= 2
            write(io, join(param_strs, ", "))
        else
            write(io, "\n")
            for (i, ps) in enumerate(param_strs)
                write(io, "    $ps")
                if i < length(param_strs)
                    write(io, ",")
                end
                write(io, "\n")
            end
        end
    end

    write(io, "):\n")

    write(io, "    \"\"\"")
    if !isempty(schema.description)
        write(io, "\n    $(schema.description)\n")
    end
    if !isempty(schema.params)
        write(io, "\n    Args:\n")
        for param in schema.params
            write(io, "        $(param.name): $(param.description)\n")
        end
    end
    write(io, "    \"\"\"\n```\n\n")

    return String(take!(io))
end

"""
Generate tool definition in Minimal style.
"""
function generate_tool_definition_minimal(schema::ToolSchema)::String
    io = IOBuffer()

    write(io, "### `$(schema.name)`\n\n")

    if !isempty(schema.description)
        write(io, "/// $(schema.description)\n")
    end

    write(io, "```\n$(schema.name)(")

    if !isempty(schema.params)
        if length(schema.params) <= 2
            param_strs = String[]
            for param in schema.params
                opt = param.required ? "" : "?"
                push!(param_strs, "$(param.name)$(opt): $(param.type)")
            end
            write(io, join(param_strs, ", "))
            write(io, ")\n```\n\n")
        else
            write(io, "\n")
            for param in schema.params
                opt = param.required ? "" : "?"
                desc = isempty(param.description) ? "" : "  # $(param.description)"
                write(io, "    $(param.name)$(opt): $(param.type)$(desc)\n")
            end
            write(io, ")\n```\n\n")
        end
    else
        write(io, ")\n```\n\n")
    end

    return String(take!(io))
end

# ============================================================================
# Batch Generation
# ============================================================================

"""
Generate a tool definition section for the system prompt.
Takes a vector of ToolSchema and formats them for the LLM.
"""
function generate_tool_definitions(schemas::Vector{ToolSchema}; header::String="## Available Tools\n\n", style::CallStyle=get_default_call_style())::String
    io = IOBuffer()
    write(io, header)

    for (i, schema) in enumerate(schemas)
        write(io, generate_tool_definition(schema; style))
        if i < length(schemas)
            write(io, "\n")
        end
    end

    return String(take!(io))
end

"""
Generate complete system prompt section for CallFormat.
Includes format documentation and tool definitions.
"""
function generate_system_prompt(schemas::Vector{ToolSchema}; style::CallStyle=get_default_call_style())::String
    io = IOBuffer()

    write(io, generate_format_documentation(style))
    write(io, "\n\n")
    write(io, generate_tool_definitions(schemas; style))

    return String(take!(io))
end

# ============================================================================
# Helper Functions
# ============================================================================

"""Convert type to Python type hint"""
function python_type(t::String)::String
    type_map = Dict(
        "string" => "str",
        "number" => "int | float",
        "integer" => "int",
        "boolean" => "bool",
        "null" => "None",
        "string[]" => "list[str]",
        "object" => "dict",
        "code" => "codeblock",
        "codeblock" => "codeblock"
    )
    get(type_map, lowercase(t), t)
end

"""Convert type to short form for concise style"""
function short_type(t::String)::String
    type_map = Dict(
        "string" => "str",
        "number" => "num",
        "integer" => "int",
        "boolean" => "bool",
        "null" => "null",
        "string[]" => "str[]",
        "object" => "obj",
        "code" => "```",
        "codeblock" => "```"
    )
    get(type_map, lowercase(t), t)
end

# ============================================================================
# Schema Helpers
# ============================================================================

"""
Create a simple tool schema (no code block).
"""
function simple_tool_schema(;
    name::String,
    description::String="",
    params::Vector{Tuple{String,String,String,Bool}}=Tuple{String,String,String,Bool}[]  # (name, type, desc, required)
)::ToolSchema
    param_schemas = [
        ParamSchema(name=n, type=t, description=d, required=r)
        for (n, t, d, r) in params
    ]
    ToolSchema(name=name, params=param_schemas, description=description)
end

"""
Create a tool schema with code block parameter.
"""
function code_tool_schema(;
    name::String,
    description::String="",
    params::Vector{Tuple{String,String,String,Bool}}=Tuple{String,String,String,Bool}[],
    code_param::Tuple{String,String,Bool}=("content", "Code content", true)  # (name, desc, required)
)::ToolSchema
    param_schemas = [
        ParamSchema(name=n, type=t, description=d, required=r)
        for (n, t, d, r) in params
    ]
    push!(param_schemas, ParamSchema(
        name=code_param[1],
        type="codeblock",
        description=code_param[2],
        required=code_param[3]
    ))
    ToolSchema(name=name, params=param_schemas, description=description)
end

"""
Convert a NamedTuple schema to ToolSchema.
This allows tools using the old NamedTuple format to work with CallFormat.
"""
function namedtuple_to_tool_schema(schema::NamedTuple)::ToolSchema
    params = ParamSchema[]
    for p in get(schema, :params, [])
        push!(params, ParamSchema(
            name=string(p.name),
            type=string(get(p, :type, "string")),
            description=string(get(p, :description, "")),
            required=get(p, :required, true)
        ))
    end
    ToolSchema(
        name=string(schema.name),
        params=params,
        description=string(get(schema, :description, ""))
    )
end

export namedtuple_to_tool_schema
