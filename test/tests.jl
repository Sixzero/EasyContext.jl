using EasyContext: process_jl_file
using Test

@testset "process_jl_file tests" begin
    bigfile = "test/edgecases/doc_module.jl"
    defs = process_jl_file(bigfile)
    @show defs

    @testset "First definition" begin
        def = defs[1]
        @test def.start_line_code == 1
        @test def.end_line_code == 19
        @test startswith(def.chunk, "\"\"\"")
        @test endswith(def.chunk, "\"\"\"")
        @test occursin("GR is a universal framework for cross-platform visualization applications.", def.chunk)
    end

    @testset "Second definition" begin
        def = defs[2]
        @test def.start_line_code == 22
        @test def.end_line_code == 25
        @test occursin("@static if isdefined(Base, :Experimental)", def.chunk)
        @test occursin("Base.Experimental.@optlevel 1", def.chunk)
    end

    @testset "Third definition" begin
        def = defs[3]
        @test def.start_line_code == 27
        @test def.end_line_code == 30
        @test occursin("if haskey(ENV, \"WAYLAND_DISPLAY\")", def.chunk)
        @test occursin("using Qt6Wayland_jll", def.chunk)
    end

    @testset "Include statements" begin
        @test defs[end-2].chunk == "include(\"js.jl\")"
        @test defs[end-2].start_line_code == 4538
        @test defs[end-2].end_line_code == 4538

        @test defs[end-1].chunk == "include(\"precompile.jl\")"
        @test defs[end-1].start_line_code == 4540
        @test defs[end-1].end_line_code == 4540
    end

    @testset "Last definition" begin
        def = defs[end]
        @test def.chunk == "_precompile_()"
        @test def.start_line_code == 4541
        @test def.end_line_code == 4541
    end

    @testset "Specific definition" begin
        def = defs[22]
        @test def.chunk == "include(\"preferences.jl\")"
        @test def.start_line_code == 279
        @test def.end_line_code == 279
    end
end

#%%

@testset "flexible_module.jl tests" begin
    bigfile = "test/edgecases/flexible_module.testexample.jl"
    defs = process_jl_file(bigfile)

    @testset "Definition line ranges" begin
        # First three definitions
        @test (defs[1].start_line_code, defs[1].end_line_code) == (3, 65)
        @test (defs[2].start_line_code, defs[2].end_line_code) == (67, 102)
        @test (defs[3].start_line_code, defs[3].end_line_code) == (107, 107)
        
        # Last three definitions
        @test (defs[end-2].start_line_code, defs[end-2].end_line_code) == (928, 928)
        @test (defs[end-1].start_line_code, defs[end-1].end_line_code) == (930, 964)
        @test (defs[end].start_line_code, defs[end].end_line_code) == (971, 988)

        # Specific definition
        @test (defs[22].start_line_code, defs[22].end_line_code) == (930, 964)
    end

    @testset "Definition chunks" begin
      @show defs[end-2].chunk
        # @test startswith(defs[end-2].chunk, "function format_time(ts::Number...)")
        # @test defs[end-1].chunk == "format_percentage(x::Number) = @sprintf(\"%.2f%%\", x * 100)"
        # @test startswith(defs[end].chunk, "function benchmark_and_profile(f; time=1.0, kwargs...)")
        # @test startswith(defs[22].chunk, "function format_time(ts::Number...)")
    end
end
#%%
@testset "HistoricalStdlibs.jl tests" begin
  bigfile = "test/edgecases/HistoricalStdlibs.jl"
  defs = process_jl_file(bigfile)

  @testset "Definition line ranges" begin
      # First three definitions
      @test (defs[1].start_line_code, defs[1].end_line_code) == (1, 1)
      @test (defs[2].start_line_code, defs[2].end_line_code) == (3, 3)
      @test (defs[3].start_line_code, defs[3].end_line_code) == (11, 11)

      # Last three definitions
      @test (defs[end-2].start_line_code, defs[end-2].end_line_code) == (3, 3)
      @test (defs[end-1].start_line_code, defs[end-1].end_line_code) == (11, 11)
      @test (defs[end].start_line_code, defs[end].end_line_code) == (16, 44)
  end

  @testset "Definition chunks" begin
      @test defs[1].chunk == "using Base: UUID"
      @test defs[2].chunk == "const DictStdLibs = Dict{UUID,Tuple{String,Union{VersionNumber,Nothing}}}"
      @test defs[3].chunk == "const STDLIBS_BY_VERSION = Pair{VersionNumber, DictStdLibs}[]"
  end

end