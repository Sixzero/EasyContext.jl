using Test
using EasyContext: CommandTag, parse_tag

@testset "CommandTag Parser Tests" begin
    @testset "Basic CommandTag Parsing" begin
        text = """
        MODIFY path/to/file force=true verbose=false arg3
        This is content
        Multiple lines
        /MODIFY
        """
        tags = parse_tag(text)
        @test length(tags) == 1
        @test tags[1].name == "MODIFY"
        @test tags[1].args == ["path/to/file", "arg3"]
        @test tags[1].kwargs == Dict("force"=>"true", "verbose"=>"false")
        @test tags[1].content == "This is content\nMultiple lines"
    end

    @testset "Multiple Tags" begin
        text = """
        TEST arg1 debug=true
        Test content
        /TEST

        CREATE file.txt owner=user
        File content
        /CREATE
        """
        tags = parse_tag(text)
        @test length(tags) == 2
        @test tags[1].name == "TEST"
        @test tags[2].name == "CREATE"
        @test tags[1].args == ["arg1"]
        @test tags[2].kwargs["owner"] == "user"
    end

    @testset "Empty Content" begin
        text = """
        EMPTY
        /EMPTY
        """
        tags = parse_tag(text)
        @test length(tags) == 1
        @test tags[1].content == ""
    end

    @testset "Error Cases" begin
        @test_throws ErrorException parse_tag("""
        OPEN
        content
        /DIFFERENT
        """)

        @test_throws ErrorException parse_tag("""
        OPEN
        content
        """)

        @test_throws ErrorException parse_tag("""
        /CLOSE
        """)
    end


    @testset "Whitespace Handling" begin
        text = """
        TAG   arg1   key=value  
           Content with spaces   
        /TAG"""
        tags = parse_tag(text)
        @test length(tags) == 1
        @test tags[1].args == ["arg1"]
        @test tags[1].kwargs["key"] == "value"
        @test tags[1].content == "Content with spaces"
    end
end
