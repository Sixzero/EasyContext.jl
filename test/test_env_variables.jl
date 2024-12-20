using Test
include("test_gmail.jl")  # This will import the constants

@testset "Gmail Environment Variables" begin
    # Test if environment variables are set
    @test !isempty(ENV["GMAIL_CLIENT_ID"])
    @test !isempty(ENV["GMAIL_CLIENT_SECRET"])
    @test !isempty(ENV["GMAIL_REDIRECT_URI"])

    # Test if constants are set correctly
    @test CLIENT_ID == ENV["GMAIL_CLIENT_ID"]
    @test CLIENT_SECRET == ENV["GMAIL_CLIENT_SECRET"]
    @test REDIRECT_URI == ENV["GMAIL_REDIRECT_URI"]
    @test SCOPE == "https://www.googleapis.com/auth/gmail.readonly"

    # Test default value for REDIRECT_URI
    withenv("GMAIL_REDIRECT_URI" => nothing) do
        @test get(ENV, "GMAIL_REDIRECT_URI", "http://localhost:8080/callback") == "http://localhost:8080/callback"
    end
end
