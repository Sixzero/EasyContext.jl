using EasyContext
using EasyContext: CohereEmbedder, get_embeddings_document, get_embeddings_query, get_embeddings_image
using Test
using LinearAlgebra
using Base64

@testset "Cohere Image-Text Similarity" begin
    # Skip tests if no API key is available
    if !haskey(ENV, "COHERE_API_KEY")
        @warn "Skipping Cohere image-text similarity tests: No COHERE_API_KEY found in environment"
        return
    end
    
    # Real image with "banana" text
    banana_image_base64 = "iVBORw0KGgoAAAANSUhEUgAAAMgAAABkCAAAAADm7SDXAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAACYktHRAD/h4/MvwAAAAd0SU1FB+kFFgkHLDJFpnIAAAKPSURBVHja7dpPSJNxHMfx96Mtt5mijErJRM3CjDLUnEJCRngKwg5hF7tJkgUdQgLP0rmDBN66Bp40vHQIumxFq6Q/Ztey1JyB0txw3w4bdO3ZI/y+xPd9G5/L78WeZw8PzBP+j8pcH8AgBlGeQbRlEG0ZRFsG0ZZBtGUQbRlEWwbRlkG0ZRBtGURbBtGWQbRlEG0ZRFsG0ZZBtGUQbQWEjHv3XQv2BpIk7lpQzAv0F46d6uy3eteEQsG+kVS2UYkjICRBn2vAXkH6N243RAbeFj6u32uJdsxzy/sOnPeW10brKrvnfW6lJkFqYe5YVbyG2hURkcUGKjpi5QuHGkQkF+VZrHqwnX0pX1upBYKsEWkaTst6M1Mi8rORwRXJDFVyVURSlFcPb0q+k0lfmxPIHAzlRWSCayIyztmMiCzBAxF5BJfzIjLMTV9bqQW6RxLUznhAjN+wOcPDCuAo9ABJwjMe8Jl6X5uTmz3JWAwgTQ3M7rT3A6xS1g0kGKkDMot0+NpcQCTJdQDe0wovGCzq2qpg6yNXAFI54n42J5Dl9IFTALnn9MIX2gF4wjngZT50oXC8pjo/mxNIgoMewOyv2EDx+oJPs8Xb4Ey0cNg+/GyOIGu7wPYkd0IQYQPI3tilB0jQy9/D/vtWegF+8boJT4n8uEjbloiM0rMtK5dOhCuyInKExyIiG5D0tbl4jmRCXdM090ZpWRYRebefw/HIyQ/EReQrLImILBDO+tmcPEde50bGpsvf1E+8agU4/bQzvXo34RWvntrjhaunK+RnK71g7yOKsnd2bRlEWwbRlkG0ZRBtGURbBtGWQbRlEG0ZRFsG0ZZBtGUQbRlEWwbRlkG0ZRBtGURbBtGWQbT1B+mqxdK4nz9JAAAAAElFTkSuQmCC"
    banana_image_uri = "data:image/png;base64,$banana_image_base64"
    
    # Create the embedder
    embedder = CohereEmbedder(
        model="embed-v4.0",
        verbose=false
    )
    
    # Test texts
    texts = [
        "banana",                 # Exact match
        "a yellow banana",        # Related
        "Lorem ipsum dolor sit"   # Irrelevant
    ]
    
    # Get embeddings
    image_embedding = get_embeddings_image(embedder, String[], images=[banana_image_uri])
    text_embeddings = get_embeddings_document(embedder, texts)
    
    # Calculate similarities
    similarities = [
        dot(image_embedding, text_embeddings[:, i]) / 
        (norm(image_embedding) * norm(text_embeddings[:, i]))
        for i in 1:size(text_embeddings, 2)
    ]
    
    # Print similarities for debugging
    @info "Similarities between 'banana' image and texts:" texts similarities
    
    # Test that similarities are valid
    @test all(-1.0 .<= similarities .<= 1.0)
    @test all(isfinite, similarities)
    
    # Test relative similarities
    # The exact "banana" text should be more similar to the banana image
    # than the irrelevant "Lorem ipsum" text
    @test similarities[1] > similarities[3]
    
    # The related "a yellow banana" text should also be more similar
    # than the irrelevant text
    @test similarities[2] > similarities[3]
    
    # Test query similarity
    query_embedding = get_embeddings_query(embedder, ["banana"])
    query_similarity = dot(image_embedding, query_embedding) / 
                      (norm(image_embedding) * norm(query_embedding))
    
    @info "Similarity between 'banana' image and 'banana' query:" query_similarity
    @test -1.0 <= query_similarity <= 1.0
    @test isfinite(query_similarity)
    
    # Test with get_score function if available
    if isdefined(EasyContext, :get_score)
        # Create chunks from texts
        chunks = [EasyContext.Chunk(text, i, "test") for (i, text) in enumerate(texts)]
        
        # Get scores using the image as query
        scores = EasyContext.get_score(embedder, chunks, banana_image_uri)
        
        @info "Scores between 'banana' image and text chunks:" texts scores
        
        # Test that scores are valid
        @test all(0.0 .<= scores .<= 1.0)
        @test all(isfinite, scores)
        
        # Test relative scores
        @test scores[1] > scores[3]  # "banana" > "Lorem ipsum"
        @test scores[2] > scores[3]  # "a yellow banana" > "Lorem ipsum"
    end
end