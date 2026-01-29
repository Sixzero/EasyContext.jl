# Legacy ToolTag removed - use ParsedCall from ToolCallFormat instead
# This file kept for print_tool_result utility only

export print_tool_result

print_tool_result(result) = begin
    print(Crayon(background = (35, 61, 28)))  # Set background
    print("\e[K")  # Clear to end of line with current background color
    print(result, "\e[0m")
end
