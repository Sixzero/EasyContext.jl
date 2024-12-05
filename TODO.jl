- Use Jina embedder. 
- get_context should not return the concatenated context, because of unique filtering.

- What if all the Context processors were returning the result, with the result.source and result.context fields.
And we would have a ContextNode, which would do all the tracking of source, it would be responsible to not print duplicates. It could have a title, like "Files" which would in the next I describe what exactly to do. 
, and we would have a layer which would return them in the format instead of ## Files: we would return them in:
if the function would get the title="Files" we would return <Files>
contexts_joined_numbered
</Files>
<Files UPDATED> 
contexts_of_updated_files
</Files UPDATED>
instead of the ## Files thing
So the format would be <\$title>
contextsjoined
</\$title>
and then with the UPDATED added.

- File write and also chat through a file?
- A way for AISH to control which flow it needs for its thinking.

- I would like the get_answer to use get_context, so the airag function should get split up in to part a get_context and the answering part based on get_context.

- I would much better like this if we could do this with @kwdef. Also could you do the same for the get_context_embedding. Also I would guess we could do some kind of simplification for the build_installed_package_index and the _bm25 one. I would prefer if you could print out a little bit more lines on how this idea should look like.

- In case this assertion: Not every index is larger than 1!
 is not true we should retry 2 times also I would say we should print out a warning.

### ###################################
I want aish to process the shell things instantly when they are ready.
I want REPL terminal!

### ###
I would need the ContextNode to also be able to be a functor, which can be called itself, and it should receive the RAG Results thing and work accordingly :) I guess this is the first node, which shouldn't return RAGContext, but the string context.


#%%
fix JuliaPakcages. 
- rerank functors
fix Promptingtools stream
Fix faster async shell process.
create aishREPL
#%%
#%%
in the test folder I want you to create a benchmark_create.jl which should be about creating benchmark dataset if given questions like:
question = "How to use BM25 for retrieval?"
question = "How do we add KVCache ephemeral cache for anthropic claude ai request?"
question = "How can we use DiffLib library in julia for reconstructing a 3rd file from 2 file?"
question = "Maybe we coul introduce the Chunk struct which would hold context and source and extra fields?"
question = "I would want you to use ReplMaker.jl to create a terminal for AI chat. Which would basically be the improved_readline for AISH.jl "
And what we need to do is create different tests for different solutions (codebase retrieval so some kind of file based thing, and for PkgsSearches...). 
For example in this case we need to test, what the JuliaPackageSearch returns. We need to create a target label set by using the embedder & BM25 and other things with top_n=1000 and then using Reranker with a model like as for now gpt4om, but later on claude or some really good model. 
In a file I think we should have a list of questions... these files probably going to have different formats... there will be one which will have many question = "query" assignments and some other filler codes, but probably we only need the list of questions from the file. But we might need other formattings too.
Also as a sidenote, probably to estabilish the CodebaseContextV3 best accuracy in relevancy as for target labels we probably need no vecDB thing, only Rerank. Also I think somehow we should be able to handle the current commit hash for the CodebaseContext thing.
#%%
We will need to filter the questions whether it is relevant for testing for the specific task (PkgRetrieval, CodebaseContext stuff or anything else).
#%%



2- [x] sh block és sh result tisztázása 
3- [x] virtual workspace + sima workspace-nál julia projektnél miért gondolja hogy van src folder... mit lát? nem kéne látnia milyen folderek vannak és akkor egyből tudja mit kellene tennie? 
2- [x] multiple project handling
8- [ ] SR finomhangolása
4- [x] controllability.... keyboard + signals (merge + clean repo (archive worktree... reattach later??))
# 5- delete/archive TODO vagy delete worktree...
# 5- merge javítása
2- [x] save conversation too
                              2- universal format conversation save (simple csv...)
                              8- @pcache (type safe... arrow... stb.... dir...) @mcache (@file_memo, @memo)
                              4- package for this....
                              2- @ucache (type safe... arrow... stb.... dir...) universal... so it would cache... and file cache
                              1- adopt @pcache style everywhere
                              6- automatic context selector
                              10- dinamic context SIZE!
                              - Tool usage implementation
                                10- Anthropic.jl
                                4- streaming
                                6- refactoring everything
                                6- file reading skill
# 8- tesztable... nem tesztable... too strong ... validation for automation + SR... self testing
4- [ ] port server API
2- [ ] persisting session("model") 
2- [ ] resume session 
# 4- [ ] Proxy backend!
- backend server
  2- [ ] connect/init 
  2- [ ] LOGIN APIkeys
  2- [ ] user_question streaming
  1- [ ] new_conversation
  1- [ ] select_conversation
  2- [ ] run_cell
  1- [ ] save file changes
  1- [ ] get_file
  4- [ ] diff get_whole_changes
  - settings     # /SPACE
     8- [ ] CREDIT by default.... NO API REQUIRED! (API (claude, openai))
     2- [ ] model picking (llm solve, merge, ctx seracher, embedding, perplexity)
     1- [ ] caching model enabled?
     3- [ ] autodiff model 
     1- [ ] auto/manual instantapply?
     1- [ ] autorun commands
    #  1- FIX conversation directory
    10- [ ] sync_conversation to cloud
     1- [ ] DEFAULT automatic context selector.
       1- [ ] available contexts (i information button for each) (disable... estimated size... and time)
      #  3- delete caches...
     -workspace configuration...   /SPACE
       4- [ ] workspace set
       4- [ ] ignores... folder + files...
  2- [ ] interupt till waiting for user response
 20- [ ] @spawn ... async multiple TODO...
  LATER- [ ] image support + file support (pdf, docs)
  LATER- [ ] surf internet
  LATER- [ ] computer usage

- weboldal deploy
  3- [ ] adatbázis kiválasztása amelyik szinkronizál.
  6- [ ] Authentikáció (autologin)
  2- [ ] email
  4- [ ] layout
  2- [ ] connect UI 
       later- autodeploy on local button.... till not ready... only txt-TODO...
  6- [ ] merge
 20- [ ] voice control
  4- [ ] control buttons (STOP... START SR... MERGE)
 10- [ ] workspace view (SHOW aiignore!) (popup codeview/edit monacoban?)
  2-20- [ ] blog
  later 1- todo.ai megvásárlása
  later- research results
 10- [ ] API .... automation howto  (BACKEND API kiajánlva... tulajdonképpen)
   - Profile: 
    1- [ ] Information
    2- [ ] API key
   16- [ ] Billing
    later...- NEW todolist (workspace? or something like that... or Space?... or something? Easy switch between) per company... or something like that...
    later 12- report & reporting page...
  2- [ ] pricing
  4- [ ] one screen view of todo with back/close button.
  4- [ ] design
  later- videos
  later- marketing... harcore way
1- [x] julia context
8- [ ] javascript context
later 10- [ ] rust context
later 16- [ ] c++ context
later 4-  [ ] gmail create+draft
later 4-  [ ] perplexity context
                                  6- [ ] python context
                                  2- [ ] speedup startup time
1- [ ] SysImage creation for deployment
3- [ ] safe interrupt
later 20- [ ] hosted + nem hosted usage
later  4- [ ] worskpace filestruct and folder should use the same mechanism... also aiignore extensive usage!
30- [ ] revert versions....
later- [ ] refactor tool usage to be general with PromptingTools and not
later- [ ] promptingtools recreate simpler and migrate to that
later- [ ] julia slack issue tracker solver
later- [ ] julia discouse issue tracker solver
later- [ ] julia github issue tracker solver
later- [ ] docker shipping...

- using COMPUTER is a skill: Click + Keyboard + image understanding

#
Cloud DB:
EVERYTHING in the cloud
workspace ONLY with local version! Also the path should be correct! + ONLY worktree  (barebone...)
julia ctx... cache (reconstruct it)  (barebone... + cache)
python ctx... cache (reconstruct it) (barebone... + cache)
cannot store "computer usage" state  (barebone... + cache)
cache into the SESSION

#
1 TODO = 1 AGENT
webview is a "GUI" to see AGENT process


#
- [ ] cat_file_skill
- [ ] benchmarking
- [ ] 