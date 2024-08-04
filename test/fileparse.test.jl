# ctx = RAG.build_context(index, def)
# println(join(ctx, "\n"))
using EasyContext: process_jl_file
# bigfile = "../../.julia/juliaup/julia-1.10.4+0.x64.linux.gnu/share/julia/stdlib/v1.10/Pkg/src/API.jl"
bigfile = "test/edgecases/bigfile.jl"
# bigfile = "../PromptingTools.jl/src/Experimental/RAGTools/utils.jl"
# bigfile = "../EasyContext.jl/test/edgecases/flexible_module.jl"
# bigfile = "../EasyContext.jl/test/edgecases/doc_module.jl"
# bigfile = "test/edgecases/bigfile_nomodule.jl"
# bigfile = "test/edgecases/HistoricalStdlibs.jl"
bigfile = "test/edgecases/small_module.jl"
bigfile = "test/edgecases/doc_but_nothing.jl"
bigfile = "test/edgecases/doc_module2.jl"

defs = process_jl_file(bigfile)
def = defs[1]
@show def.start_line_code, def.end_line_code
println.(split(def.chunk, "\n"))
def = defs[2]
@show def.start_line_code, def.end_line_code
println.(split(def.chunk, "\n"))
def = defs[3]
@show def.start_line_code, def.end_line_code
println.(split(def.chunk, "\n"))
def = defs[end-1]
@show def.start_line_code, def.end_line_code
def = defs[end]
@show def.start_line_code, def.end_line_code
# def = defs[22]
# @show def.start_line_code, def.end_line_code
def = defs[end-2]
@show def.start_line_code, def.end_line_code
def = defs[end-1]
@show def.start_line_code, def.end_line_code
def = defs[end]
@show def.start_line_code, def.end_line_code
;
## grab the chunks
# chunks[idx] = "$(def.file_path):$(def.start_line_code)\n" * join(lines[(def.start_line_code):(def.end_line_code)], '\n')
#%%
files = ["/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:63", "/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:64", "/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:65", "/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:66", "/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:67", "/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:68", "/home/six/.julia/packages/PrettyTables/f6dXb/src/PrettyTables.jl:69", ]
using EasyContext: process_jl_file, file_path_lineno
defs = process_jl_file.([split(f, ":")[1] for f in files]);
#%%
using EasyContext: process_jl_file, file_path_lineno
function unique_by_file_path(defs)
    seen = Set{String}()
    result = typeof(defs)()

    for def_all in defs
        def = def_all[1]
        if !(def.file_path in seen)
            push!(seen, def.file_path)
            push!(result, def_all)
        end
    end

    return result
end

defs_file_uu = unique_by_file_path(defs)
@show length(defs)
@show length(defs_file_uu)
for def in defs_file_uu
    for d in def
        # if firstline of d.chunk is in docs
        
        if file_path_lineno(d) in Set(files) && length(d.chunk)>10000 
            # for d in def_dir
            @show file_path_lineno(d), length(d.chunk)
        end
    end
end
