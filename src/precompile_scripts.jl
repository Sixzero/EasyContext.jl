
using PrecompileTools

@setup_workload begin
    @compile_workload begin
        # start("", resume=false, loop=false, contexter=EasyContextCreatorV4())
    end
end
