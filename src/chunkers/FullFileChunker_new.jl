full_file_chunker(files::Vector{<:AbstractString}) =  Dict(f => get_chunk_standard_format(f, read(f, String)) for f in files if isfile(f))
