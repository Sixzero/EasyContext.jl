
const Context = Dict{String, String}


workspace_ctx_2_string(args...) = to_string("ShellRunResults", "sh_script", scr_state, src_cont) 
workspace_ctx_2_string(args...) = to_string("Codebase", "File", scr_state, src_cont) 
pkg_ctx_2_string(args...) = to_string("Functions", "Function", scr_state, src_cont) 
python_ctx_2_string(args...) = to_string("PythonPackages", "Package", args...) 