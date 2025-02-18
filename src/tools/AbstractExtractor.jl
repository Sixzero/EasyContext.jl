
abstract type AbstractExtractor end

function execute_tools(stream_parser::E; no_confirm=false, kwargs...) where E <: AbstractExtractor
	@assert false "execute_tools is not implemented for $(E)"
end

function get_tool_results(stream_parser::E; filter_tools::Vector{DataType}=DataType[]) where {E <: AbstractExtractor}
	@assert false "get_tool_results is not implemented for $(E)"
end
