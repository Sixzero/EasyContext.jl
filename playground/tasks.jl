
task1 = "We need to switch our prompt processing to use PromptingTools stream protocol probably with the stream=true flag? Also the callback things needs to be adjusted for this."

task2 = "I would need an way to on the fly while the output is streaming, extract the shell scripts when they are finished generating, and if it is extracted we need to start their async preprocessing. It would be best if it wouldn't just rerun on the full content in the on_text always, but it would know what parts of rthe content is already processed so we would have a more efficient solution.
"
task3 = "How could we write test for extract_and_preprocess_shell_scripts with mocking it improve_code_with_LLM so it won't call out for an LLM just return the original thing."

We want to have a PyTorch like definition of the pipe that is defined in the AISHExtensionV4. We need it in a new file. Currently I have a template of the end goal we would like to have:
@kwdef struct ProModel <: AbstractPyTorchLikeForward
  project_paths::Vector{String}=String[]
  state::NamedTuple=(;)
end
function (::AbstractPyTorchLikeForward)(question::AbstractString)
    let MODEL = "claude"
    let shell_processor = ShellProcessor();
    let converstion = ConversationProcessor()
    return [
        AsyncPipe([
            Pipe([ShellContext(shell_processor)]),
            Pipe([
                QuestionAccumulatorProcessor(),
                CodebaseContextV3(),
                ReduceRankGPTReranker(;batch_size=30, model="gpt4om"),
                ContextNode(tag="Codebase", element="File"),
            ]),
            Pipe([
                JuliaPackageContext(),
                EmbeddingIndexBuilder(),
                ReduceRankGPTReranker(; batch_size=40),
                ContextNode(tag="Functions", element="Function")
            ]), 
        ]),
        saveUserMsg(converstion), converstion, StreamLLMCaller(model=MODEL, 
            on_begin=() -> empty!(shell_processor), 
            on_text=(chunk) -> begin
                shell_processor(chunk)
                print(chunk)
            end) , saveAiMsg(converstion)
    ]
end
All the Pipe things are just codes like x = a * mul(b) and operations one after the other.
This previous thing was just a concept idea... the question should be the input of questionAccumulator also I thnk in the embedddingIndexBuilder also ReduceRankGPTReranker this ConversationProcessor is going to be responsible to filter for what ContextNode is now doing to filter out things if there are too many messages in the conversation. The ConversationsProcessor should have some filed of AIState from AISH and also do the keep history length filter thing.
#%%
We already have this ShellScriptExtractor thing
@kwdef mutable struct ShellScriptExtractor
  last_processed_index::Ref{Int} = Ref(0)
  shell_scripts::OrderedDict{String, Task} = OrderedDict{String, Task}()
  full_content::String = ""
end
function extract_and_preprocess_shell_scripts(new_content::String, extractor::ShellScriptExtractor; mock=false)
  extractor.full_content *= new_content
  lines = split(extractor.full_content[extractor.last_processed_index[]+1:end], '\n')
  current_command = String[]
  in_block = false
  cmd_type = :NOTHING
  block_type = ""
  file_path = ""
  last_processed_char = extractor.last_processed_index[]
  for (i, line) in enumerate(lines)
      if startswith(line, "MODIFY ")        
          file_path = String(strip(line[8:end]))
          cmd_type = :MODIFY
      elseif startswith(line, "CREATE ")
          file_path = String(strip(line[8:end]))
          cmd_type = :CREATE
      elseif startswith(line, "```") && !in_block
          in_block = true
          block_type = String(strip(line[4:end]))
      elseif in_block && length(line)>=3 && line[1:3] == "```" && (length(line)==3 || all(isspace, line[4:end]))
          command = join(current_command, '\n')
          if cmd_type == :MODIFY
              tmp = process_modify_command(String(file_path), command)
              extractor.shell_scripts[command] = @async_showerr improve_command_LLM(tmp)
          elseif cmd_type == :CREATE
              tmp = process_create_command(String(file_path), command)
              extractor.shell_scripts[command] = @async_showerr tmp
          else
              extractor.shell_scripts[command] = @async_showerr command
              # if block_type == "sh"
              #     extractor.shell_scripts[command] = @async command
              # else
              #     extractor.shell_scripts[command] = @async command
              #     @warn "is this unhandled script parsing? $(block_type)"
              # end
          end
          current_command = String[]
          in_block = false
          block_type = ""
          cmd_type = :NOTHING
          file_path = ""
          last_processed_char = length(extractor.full_content)
      elseif in_block
          push!(current_command, line)
      end
      # if !in_block
      #     last_processed_char += length(line) + 1  # +1 for the newline
      # end
  end
  extractor.last_processed_index[] = last_processed_char
  return extractor.shell_scripts
end
The StreamLLMCaller can have another name, but it should do something what this does:
```
...`
extractor = ShellScriptExtractor()
if state.streaming
    clearline()
    print("\e[32mProcessing... \e[0m")
    cache = get_cache_setting(state.contexter, curr_conv(state))
    channel = ai_stream_safe(state, printout=false, cache=cache) 
    msg, user_meta, ai_meta = process_stream(channel, 
        on_meta_usr=meta->(clearline();println("\e[32mUser message: \e[0m$(format_meta_info(meta))"); update_last_user_message_meta(state, meta); print("\e[36m¬ \e[0m")), 
        on_text=chunk->on_text(chunk, extractor), 
        on_meta_ai=meta->println("\n\e[32mAI message: \e[0m$(format_meta_info(meta))"))
    println("")
...
```
#%%
Please rewrite the functor of the ProModel to be more like a PyTorch forward function, which assigns one output to the other, also you can use asyncmap to replace the asynPipe, idk what alse that thing does, I guess we should also take care of that.
#%%
I would think like ine EasyContextV4 we also need to return in the combined_context the question, and also I would think saving it also. and then the conversation_processor should receive this question extended thing, and yeah, I think the stre I think Pipe is colliding with the other thing defined in another file? maybe we should use that, and extrat it to another function, or could we find a better simpler solution for that part of the code?
#%%
Maybe we don't even need the pipe thing? we could just do it in a forward pytorch way too? x goes into y y goes into z and so on. Pipe is not even needed? 
#%%
I don't need sepaarate line for the innitializations, also I would say we could use still some kind of async call to all the things. the concat thing is somewhat good IMO. althought I think it has by element tag-s for each context data, the bigger picture codebase thing tags are pretty awesome, I like them.
#%% 
I still need 2 things I don't want the Processors to get initialized earlier, only when they are used, ConversationProcessor and ShellExtractor are the only 2 which are stateful, so they must be stored in the ProModel.
#%%
return question -> Pipe([ShellContext(shell_processor)])(question)
ContextNode(tag="Codebase", element="File"),
ContextNode(tag="Functions", element="Function")
where the shellContext had this:
function format_shell_results(shell_commands::AbstractDict{String, String})
  result = "<ShellRunResults>"
  for (code, output) in shell_commands
      shortened_code = get_shortened_code(code)
      result *= """
      <sh_script shortened>
      $shortened_code
      <!sh_script>
      <sh_output>
      $output
      </sh_output>
      """
  end
  result *= "</ShellRunResults>"
  return result
end
Also the ContextNode had a tag which surrounded each elements.
#%%
You don1T need the get_processor, actually it is compleetly useless there... the format thing for the ShellContext needs fixing, please think it over I think it is formatted twice right?
#%%
We need this into a file, we use this:
@kwdef mutable struct ShellScriptExtractor
  last_processed_index::Ref{Int} = Ref(0)
  shell_scripts::OrderedDict{String, Task} = OrderedDict{String, Task}()
  full_content::String = ""
end
function extract_and_preprocess_shell_scripts(new_content::String, extractor::ShellScriptExtractor; mock=false)
  extractor.full_content *= new_content
  lines = split(extractor.full_content[extractor.last_processed_index[]+1:end], '\n')
  current_command = String[]
  in_block = false
  cmd_type = :NOTHING
  block_type = ""
  file_path = ""
  last_processed_char = extractor.last_processed_index[]
  for (i, line) in enumerate(lines)
      if startswith(line, "MODIFY ")        
          file_path = String(strip(line[8:end]))
          cmd_type = :MODIFY
      elseif startswith(line, "CREATE ")
          file_path = String(strip(line[8:end]))
          cmd_type = :CREATE
      elseif startswith(line, "```") && !in_block
          in_block = true
          block_type = String(strip(line[4:end]))
      elseif in_block && length(line)>=3 && line[1:3] == "```" && (length(line)==3 || all(isspace, line[4:end]))
          command = join(current_command, '\n')
          # @show cmd_type
          # @show command
          if cmd_type == :MODIFY
              tmp = process_modify_command(String(file_path), command)
              extractor.shell_scripts[command] = @async_showerr improve_command_LLM(tmp)
          elseif cmd_type == :CREATE
              tmp = process_create_command(String(file_path), command)
              extractor.shell_scripts[command] = @async_showerr tmp
          else
              extractor.shell_scripts[command] = @async_showerr command
              # if block_type == "sh"
              #     extractor.shell_scripts[command] = @async command
              # else
              #     extractor.shell_scripts[command] = @async command
              #     @warn "is this unhandled script parsing? $(block_type)"
              # end
          end
          current_command = String[]
          in_block = false
          block_type = ""
          cmd_type = :NOTHING
          file_path = ""
          last_processed_char = length(extractor.full_content)
      elseif in_block
          push!(current_command, line)
      end
      # if !in_block
      #     last_processed_char += length(line) + 1  # +1 for the newline
      # end
  end
  extractor.last_processed_index[] = last_processed_char
  return extractor.shell_scripts
end
I think it is good right? Also we have the shell_scripts thing which we format into the context, so actually maybe we can simplify and don't need ths ShellResults thing just the formatting with this dict in thsi Extrator?
#%% TODO
Conversation processor should be responsible for the  
#%% TODO
We need a way to modify the system message of the ConversationProcessor somewhat similarly as it was done with the AISHExtensionV4.
