using EasyContext, PromptingTools
using DataStructures: OrderedDict
using EasyContext: create_rankgpt_prompt_v2, create_rankgpt_prompt_v3

function test_reranker(model)
    # Create test documents with varying sizes and content
    docs = [
        "function add(x) = x + 1",                                    # Simple math function
        "function subtract(x) = x - 1\n" * "x"^1000,                 # Math with padding
        "struct Calculator\n    x::Int\nend\n" * "y"^1500,           # Simple struct with padding
        "function process(x) = x + 1\n" * "z"^1200,                  # Similar to add but with noise
        "# Helper utility\nfunction helper() = 0",                   # Utility function
        """function calculate_complex(x, y)                         # Complex calculation
            result = (x + y) * 2
            sqrt(abs(result))
        end""" * "a"^300,
        """@doc \"\"\"                                             # Documented function
            parse_input(x::String)
            Parses and validates input string
        \"\"\"
        function parse_input(x::String)
            # Implementation
        end""",
        """struct MathEngine                                       # Complex struct
            precision::Int
            operations::Vector{Function}
            cache::Dict{Symbol,Any}
        end""" * "b"^800,
        """# Configuration module                                  # Config stuff
        module Config
            const DEFAULT_PRECISION = 2
            const SUPPORTED_MODES = ["fast", "precise"]
        end""" * "c"^1200,
        """function validate!(x::Vector)                          # Input validation
            @assert !isempty(x) "Input cannot be empty"
            @assert all(>(0), x) "All elements must be positive"
        end""",
        """abstract type AbstractProcessor end                    # Type hierarchy
        struct BasicProcessor <: AbstractProcessor
            name::String
        end""" * "d"^1500,
        """using Test                                            # Test suite
        @testset "Math Tests" begin
            @test add(1) == 2
            @test subtract(5) == 4
        end""",
    ]
    
    println("\nTesting model: $model")
    println("-" ^ 40)
    
    chunks = OrderedDict(zip(string.(1:length(docs)), docs))
    
    # Test with LinearGrowthBatcher
    reranker = EasyContext.ReduceGPTReranker(
        batch_size=4, 
        top_n=3, 
        model=model,
        verbose=1,
        rank_gpt_prompt_fn=create_rankgpt_prompt_v2,
        batching_strategy=EasyContext.LinearGrowthBatcher()
    )
    
    println("\nUsing LinearGrowthBatcher (order-preserving):")
    @time result = reranker(chunks, "I need a function that adds 1 to a number")
    println("\nTop results:")
    for (k,v) in result
        println("$k: ", first(split(v, '\n')), "...")
    end

    # # Test with TokenBalancedBatcher
    # reranker = EasyContext.ReduceGPTReranker(
    #     batch_size=4, 
    #     top_n=3, 
    #     model=model,
    #     verbose=1,
    #     batching_strategy=EasyContext.TokenBalancedBatcher()
    # )
    
    # println("\nUsing TokenBalancedBatcher:")
    # @time result = reranker(chunks, "I need a function that adds 1 to a number")
    # println("\nTop results:")
    # for (k,v) in result
    #     println("$k: ", first(split(v, '\n')), "...")
    # end

end

# for model in ["gem15f", "tqwen25b72", "gpt4om", "dscode"]
# for model in ["gpt4om", ]
for model in ["dscode", ]
    test_reranker(model)
end
