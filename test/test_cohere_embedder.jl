using EasyContext
using EasyContext: CohereEmbedder, get_embeddings_document, get_embeddings_image
using Test
using Base64
using LinearAlgebra

@testset failfast=true "Cohere Embedder" begin
    @testset "Text Embeddings" begin
        # Skip tests if no API key is available
        if !haskey(ENV, "COHERE_API_KEY")
            @warn "Skipping Cohere text embedding tests: No COHERE_API_KEY found in environment"
            return
        end
        
        embedder = CohereEmbedder(
            model="embed-v4.0",
            verbose=false
        )
        
        # Test with a simple text
        texts = ["This is a test sentence for embedding."]
        embeddings = get_embeddings_document(embedder, texts)
        
        @test size(embeddings, 1) > 0  # Should have some dimensions
        @test size(embeddings, 2) == 1  # Should have one column (one text)
        @test all(isfinite, embeddings)  # All values should be finite
        
        # Test with multiple texts
        texts = ["First test sentence.", "Second test sentence."]
        embeddings = get_embeddings_document(embedder, texts)
        
        @test size(embeddings, 2) == 2  # Should have two columns (two texts)
    end
    
    @testset "Image Embeddings" begin
        # Skip tests if no API key is available
        if !haskey(ENV, "COHERE_API_KEY")
            @warn "Skipping Cohere image embedding tests: No COHERE_API_KEY found in environment"
            return
        end
        
        # Create a simple test image data URI (1x1 pixel transparent PNG)
        # This is a minimal valid PNG image
        test_png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        test_image_uri = "data:image/png;base64,$test_png_base64"
        
        # Create the embedder
        embedder = CohereEmbedder(
            model="embed-v4.0",
            verbose=false
        )
        
        # Test embedding a single image
        embedding = get_embeddings_image(embedder, String[], images=[test_image_uri])
        
        # Check that we got a valid embedding
        @test size(embedding, 1) > 0  # Should have some dimensions
        @test size(embedding, 2) == 1  # Should have one column (one image)
        @test all(isfinite, embedding)  # All values should be finite
        
        # Test embedding multiple images
        embeddings = get_embeddings_image(embedder, String[], images=[test_image_uri, test_image_uri])
        @test size(embeddings, 2) == 2  # Should have two columns (two images)
    end
    
    @testset "Mixed Text and Image Comparison" begin
        # Skip tests if no API key is available
        if !haskey(ENV, "COHERE_API_KEY")
            @warn "Skipping Cohere mixed embedding tests: No COHERE_API_KEY found in environment"
            return
        end
        
        # Create a simple test image data URI
        test_png_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        test_image_uri = "data:image/png;base64,$test_png_base64"
        
        # Create the embedder
        embedder = CohereEmbedder(
            model="embed-v4.0",
            verbose=false
        )
        
        # Test embedding both image and text
        image_embedding = get_embeddings_image(embedder, String[], images=[test_image_uri])
        text_embedding = get_embeddings_document(embedder, ["A test image"])
        
        # Calculate similarity
        similarity = dot(image_embedding, text_embedding) / (norm(image_embedding) * norm(text_embedding))
        
        # Check that similarity is a valid number between -1 and 1
        @test -1.0 <= similarity <= 1.0
        @test isfinite(similarity)
    end
    
end