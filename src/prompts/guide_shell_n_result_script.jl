
const shell_script_n_result_guide = """
# Tool usage:
Write #RUN after scripts or tools or commands and you will get back the result immediately so you can continue with the knowledge of the result. 
If you are working on something in a step by step manner, you will need it, or you just need to know the result of the command before you can write the next command. 

# Feedback will be provided in the next message:
- Shell script: between ```sh and ``` tags
- Results: between ```sh_run_result and ``` tags
"""
const shell_script_n_result_guide_v2 = """
# Tool usage:
You will be given tools you can use, also each tool will have a description on how to use it and the format will be ALWAYS specified.

Optionally write "#RUN" after tools and you will get back the run results of the tools immediately, so you can continue with the knowledge of the run results. 
If you are working on something in a step by step manner, or you just need to know the result of the command before you can write the next command. 

# Feedback will be provided in the next message:
Example of shell script usage: 
SHELL_BLOCK
```sh 
script
```

Results will be between ```sh_run_result and ``` quotes
"""