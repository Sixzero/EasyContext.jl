using Test
using EasyContext
using EasyContext: CodeBlock, MELD, VIMDIFF, MELD_PRO, cmd_all_info_modify, CURRENT_EDITOR

@testset "Editor Commands" begin
    # Create a temporary test file
    test_file = tempname()
    write(test_file, "original content")
    
    test_content = "new content"
    
    @show "OK"
    # Test VIMDIFF
    EasyContext.CURRENT_EDITOR = VIMDIFF
    cb_vimdiff = CodeBlock(type=:MODIFY, language="julia", file_path=test_file, 
                          content="test", postcontent=test_content)
    cmd_str = "vimdiff $test_file <(echo -e '$test_content')"
    vimdiff_cmd = `zsh -c $cmd_str`
    vimdiff_cmd |> run
    # @test occursin("vimdiff", cmd_all_info_modify(vimdiff_cmd))
    
    # Test MELD_PRO
    EasyContext.CURRENT_EDITOR = MELD_PRO
    cb_meld_pro = CodeBlock(type=:MODIFY, language="julia", file_path=test_file, 
                           content="test", postcontent=test_content)
    cmd_str = "meld-pro $test_file - <<'EOF'\n$(test_content)"
    meld_pro_cmd = `zsh -c $cmd_str`
    @show meld_pro_cmd
    # @test occursin("meld-pro", cmd_all_info_modify(meld_pro_cmd))
    
    # Cleanup
    rm(test_file, force=true)
end
