using EasyContext
using EasyContext: CohereEmbedder, create_cohere_embedder, get_embeddings_document, get_embeddings_query, get_embeddings_image, get_score, TopK, search
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
    banana_image_base64 = "iVBORw0KGgoAAAANSUhEUgAAAMgAAABkCAAAAADm7SDXAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAACYktHRAD/h4/MvwAAAAd0SU1FB+kFFgkRMU3bf3wAAAJWSURBVHja7do/aBNhGMfx752hdEjaWlP81xgVVFBLqg6KHXTQLiIdxMGlOllQs4lC0bUogroqSEYruBREB1FCBQWpVVoUOwgWpFIaq6ARiY2PQxIaIUPu3pI+yPNZrtzvHfIlCdchnvB/8Jf7BViIhShnIdpYiDYWoo2FaGMh2liINhaijYVoYyHaWIg2FqKNhWhjIdpYiDYWoo2FaGMh2oQP6faGl/vFL02IMhaijYUA5NIbmzekvwAwd6dvWzTWNZgrTd3e8M9LW5rX9E8HX8ORsFJcT9DWDomPIiIDQKsPiQ/l9VYKz4e1M4HXUFxCYp1PRZ4l6fkjIkOXJ/JSGN3LwfIa3/SgkL8XY0CCrg0P8cdERCYiPFq8O9/Bu9IamRIRuUZcgq6huHxHevcAdB3h/uK9lft5UfrrxFaAY+Rmg68huIQcqFzGAd6c3h71PG+EmdLtFADrPb4FX0OIOISsq1zmgNtnipHNq5p4P5uvXpv84u/gawhL8BwRgOl08cL81PNs9hDlHxd6VUeCriG4vCPlz8FnOmCksOtq9c1/uax1cnlHspXLbvjEDgC+v6x10mVtQMjjVwCTDzkOrbwFYKjmp9xlbUBItO8JjB5d6OmFw7w+/4Ovg1faa510Wevl8EC8maSlpfIvSj/4cZ9TJ7lYWu+Wjq1gMuja8Afi6rFzbb86z44nATI3dkYW9mUytY+6rPXx7JfYyliINhaijYVoYyHaWIg2FqKNhWhjIdpYiDYWoo2FaGMh2liINhaijYVoYyHaWIg2FqKNhWhjIdr8BexLIpUXfXouAAAAAElFTkSuQmCC"
    banana_image_uri = "data:image/png;base64,$banana_image_base64"
    
    # Create the embedder
    embedder = create_cohere_embedder(
        model="embed-v4.0",
        verbose=false
    )
    
    # Test texts
    texts = [
        "banana",                 # Exact match
        "a banana text",        # Related
        "a yellow banana",        # Related
        "Lorem ipsum dolor sit",   # Irrelevant
        "not banana",   # Irrelevant
        "a julia nyelv egy nagyon szép nyelv"   # Irrelevant
    ]
    
    # Get embeddings
    image_embedding = get_embeddings_image(embedder, String[], images=[banana_image_uri])
    text_embeddings = get_embeddings_document(embedder, texts)
    text_embeddings_just = get_embeddings_document(embedder, ["just a banana"])
    
    similarities = get_score(Val(:CosineSimilarity), text_embeddings, text_embeddings_just[:,1])
    @show similarities
    similarities = get_score(Val(:CosineSimilarity), text_embeddings, reshape(image_embedding, :))
    
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

    result = search(TopK(;embedder, top_k=2), texts, ""; query_images=[banana_image_uri])
    @test result[1] in texts[1:2]
    @test result[2] in texts[1:2]
    
end