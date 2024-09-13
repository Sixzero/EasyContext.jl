using EasyContext: EasyContextCreator, EasyContextCreatorV2, EasyContextCreatorV3
using AISH: initialize_ai_state, process_question, main, start, SimpleContexter

# main(;contexter=SimpleContexter())
# main(;contexter=EasyContextCreatorV2())
main(;contexter=EasyContextCreatorV3())

#%%
using EasyContext: build_installed_package_index
index = build_installed_package_index(; force_rebuild=true)
#%%
using AISH: initialize_ai_state, process_question
using EasyContext: EasyContextCreator
contexter = EasyContextCreator()
resume = true
project_paths=[""]
ai_state = initialize_ai_state(;contexter, resume, project_paths);
message = "I would want to print out how many relevant files got selected. With an informative color."
process_question(ai_state, message);
#%%
message = "Could you please implement the parser which is used in the GolemChunker also for python syntax too? So it pretty much parses and chunks fuctions separately and also if a function has docs before it then also attach that to the function? I would need a separate file like GolemPythonChunker.jl."
process_question(ai_state, message);
#%%
message = """
Could you please make it so that there is also a Golem for julia not just for python? and the original GolemSourceChunker should be a codebase which basically automatically uses the right chunker for the right code. So it should use julia source chunker for julia .jl files and python for the .py files.
"""
process_question(ai_state, message);
#%%
message = """
How are we able to process all the files in a julia package? We would also need a way to list all the python package files which belong to the python package, so we can chunk it.
"""
process_question(ai_state, message);
#%%
message = """
function get_chunks(chunker::GolemSourceChunker,
this function should support both python and julia packages... idk how we could do that.
"""
process_question(ai_state, message);
#%%
message = """
Pkg.project().dependencies
only gives back I think the dependencies of the current project, because we are not finding many installed julia packages with the:
julia_context = get_context("How do I use DataFrames?", language=:julia)
"""
process_question(ai_state, message);
#%%
message = """
Give me an example how you could use the package chunking. How could I call it?
the 
function get_context(question::String; index=nothing, rag_conf=nothing, force_rebuild=false)
    if isnothing(index)
        index = GLOBAL_INDEX[]
        if force_rebuild || isnothing(index)
            index = build_installed_package_index(; force_rebuild)
        end
    end
    
    if isnothing(rag_conf) || isnothing(kwargs)
        rag_conf, kwargs = get_rag_config()
    end
    
    result = RAG.retrieve(rag_conf.retriever, index, question; 
        return_all=true,
        kwargs.retriever_kwargs...
    )
    
    RAG.build_context!(rag_conf.generator.contexter, index, result)
    # result.context
    result
end
now automatically adds all the installed julia packages, but I would need I think the same for python, and also I would need I guess a way to specify this, whether I want to build context from python package or julia right?
"""
process_question(ai_state, message);
#%%
message = """Is .jl and .py package handling good? Julia should check whether the given package is installed on the system, not only project wide things.
"""
process_question(ai_state, message);
#%%
message = """I would want to not use pkg walkdir for walking julia packages, but I would want what is in PkgManager.jl to follow includes recursively, and track which module are we in. So if we from module Pkg1 we also have a module PkgInner then we are in Pk1 and PkgInner, so we essentially need to keep a stack of the module level we are in.
"""
process_question(ai_state, message);
#%%
message = """I would also need to print out styled the found the contexts sources like we do this for found files.
"""
process_question(ai_state, message);
#%%
message = """I think you didn't add the get_context print. We need it to also print out the sources there too.
"""
process_question(ai_state, message);
#%%
julia_context = get_context("How do I use DataFrames?", language=:julia)
# python_context = get_context("How do I use pandas?", language=:python)
#%%
using EasyContext: get_julia_package_files
get_julia_package_files("DataFrames")
#%%

all_files = get_project_files(".")

selected_files, fileindex = get_relevant_files(message, all_files)