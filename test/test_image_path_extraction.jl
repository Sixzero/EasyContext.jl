using Test
using EasyContext
using EasyContext: extract_image_paths, is_image_path

@testset failfast=true "Image Path Extraction Tests" begin
    @testset "Basic image path detection" begin
        @test is_image_path("\"image.png\"")
        @test is_image_path("'photo.jpg'")
        @test !is_image_path("image.txt")
        @test !is_image_path("\"document.pdf\"")
    end

    @testset "Extract single image path" begin
        content = "Here is an image \"test.png\" in text"
        paths = extract_image_paths(content)
        @test length(paths) == 1
        @test paths[1] == "test.png"
    end

    @testset "Extract multiple image paths" begin
        content = """
        Multiple images:
        "path/to/image1.jpg"
        'path/to/image2.png'
        "path with spaces/image3.jpeg"
        """
        paths = extract_image_paths(content)
        @test length(paths) == 3
        @test "path/to/image1.jpg" in paths
        @test "path/to/image2.png" in paths
        @test "path with spaces/image3.jpeg" in paths
    end

    @testset "Handle spaces in paths" begin
        content = "\"my folder/cool image.png\""
        paths = extract_image_paths(content)
        @test length(paths) == 1
        @test paths[1] == "my folder/cool image.png"
    end

    @testset "Mixed content with images" begin
        content = """
        Here is some text
        with "image1.jpg" and
        some 'path/with space/image2.png'
        and more text
        """
        paths = extract_image_paths(content)
        @test length(paths) == 2
        @test "image1.jpg" in paths
        @test "path/with space/image2.png" in paths
    end

    @testset "No images in content" begin
        content = "Just some regular text without images"
        @test isempty(extract_image_paths(content))
    end

    @testset "Handle different quote types" begin
        content = """
        Single quotes: 'image1.png'
        Double quotes: "image2.jpg"
        """
        paths = extract_image_paths(content)
        @test length(paths) == 2
        @test "image1.png" in paths
        @test "image2.jpg" in paths
    end

    @testset "Handle unquoted paths" begin
        content = "/home/six/Pictures/Screenshots/Screenshot from 2025-02-12 11-15-39.png  /home/six/Pictures/Screenshots/Screenshot from 2025-02-12 11-15-31.png relative.png"
        paths = extract_image_paths(content)
        @test length(paths) == 2
        @test "/home/six/Pictures/Screenshots/Screenshot from 2025-02-12 11-15-39.png" in paths
        @test "/home/six/Pictures/Screenshots/Screenshot from 2025-02-12 11-15-31.png" in paths
        @test !("relative.png" in paths)
    end

    @testset "Unquoted vs quoted paths" begin
        content = """
        Absolute unquoted: /path/to/image1.png
        Relative quoted: "relative/path/image2.jpg"
        Relative unquoted: relative/path/image3.png
        """
        paths = extract_image_paths(content)
        @test length(paths) == 2
        @test "/path/to/image1.png" in paths
        @test "relative/path/image2.jpg" in paths
        @test !("relative/path/image3.png" in paths)
    end
end
