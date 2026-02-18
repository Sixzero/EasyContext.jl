export AbstractExtractor, any_tool_needs_approval, get_tool_results, process_native_tool_calls!, collect_tool_messages

abstract type AbstractExtractor end

function extract_tool_calls(new_content::String, extractor::E, io; kwargs...) where E <: AbstractExtractor
	@assert false "extract_tool_calls is not implemented for $(E)"
end

function any_tool_needs_approval(extractor::E) where E <: AbstractExtractor
	@assert false "any_tool_needs_approval is not implemented for $(E)"
end

function get_tool_results(stream_parser::E; filter_tools::Vector{DataType}=DataType[]) where {E <: AbstractExtractor}
	@assert false "get_tool_results is not implemented for $(E)"
end

"""Process tool_calls from a native API response. Override per extractor type."""
function process_native_tool_calls!(extractor::E, tool_calls::Vector, io; kwargs...) where E <: AbstractExtractor
	@assert false "process_native_tool_calls! is not implemented for $(E)"
end

"""Collect results as ToolMessages for native API round-trip. Override per extractor type."""
function collect_tool_messages(extractor::E; kwargs...) where E <: AbstractExtractor
	@assert false "collect_tool_messages is not implemented for $(E)"
end

