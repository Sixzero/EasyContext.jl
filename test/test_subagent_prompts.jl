using Test
using EasyContext
using EasyContext: machine_routing_block, explore_sys_prompt, review_sys_prompt

@testset "sub-agent prompt building" begin
    alias_pc = (tool=1, edge_id="e1", alias="bash_pc")
    bare = (tool=1, edge_id="e1", alias="bash")

    @testset "machine_routing_block gate" begin
        @test machine_routing_block(Any[]; stale_tail="x") == ""
        @test machine_routing_block(Any[bare]; stale_tail="x") == ""              # bare alias: no routing
        @test machine_routing_block(Any[1, "str"]; stale_tail="x") == ""          # plain tool types
        @test occursin("MACHINE ROUTING", machine_routing_block(Any[alias_pc]; stale_tail="TAIL."))
        @test occursin("TAIL.", machine_routing_block(Any[alias_pc]; stale_tail="TAIL."))
        # edge-alias shape required: alias without edge_id, or non-string alias, don't trigger
        @test machine_routing_block(Any[(tool=1, alias="bash_pc")]; stale_tail="x") == ""
        @test machine_routing_block(Any[(tool=1, edge_id="e", alias=:bash_pc)]; stale_tail="x") == ""
    end

    @testset "prompt spacing and gating" begin
        for (fn, marker) in ((explore_sys_prompt, "EXPLORATION PASS ONLY"),
                             (review_sys_prompt, "REVIEW PASS ONLY"))
            single = fn(Any[bare])
            multi = fn(Any[alias_pc])
            @test !occursin("MACHINE ROUTING", single)
            @test occursin("MACHINE ROUTING", multi)
            for p in (single, multi)
                @test occursin(marker, p)
                @test !occursin("\n\n\n", p)   # exactly one blank line between paragraphs
                @test !startswith(p, "\n") && !endswith(p, "\n")
            end
        end
    end
end
