export AbstractExtractor, are_tools_cancelled, get_tool_results

abstract type AbstractExtractor end

function extract_tool_calls(new_content::String, extractor::E, io; kwargs...) where E <: AbstractExtractor
	@assert false "extract_tool_calls is not implemented for $(E)"
end

function execute_tools(stream_parser::E; no_confirm=false, kwargs...) where E <: AbstractExtractor
	@assert false "execute_tools is not implemented for $(E)"
end

function are_tools_cancelled(extractor::E) where E <: AbstractExtractor
	@assert false "are_tools_cancelled is not implemented for $(E)"
end

function get_tool_results(stream_parser::E; filter_tools::Vector{DataType}=DataType[]) where {E <: AbstractExtractor}
	@assert false "get_tool_results is not implemented for $(E)"
end
