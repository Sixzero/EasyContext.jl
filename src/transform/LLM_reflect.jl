
using PromptingTools

export LLM_reflect, is_continue, LLM_reflect_condition

function LLM_reflect(ctx_question, ctx_shell, ctx_test, new_ai_msg)
    prompt = """
    You are an AI assistant specialized in determining what are the problems and what have to be repaired or the task actually fulfulled and DONE or in certain case you have to deteck if the solution actually stucked and cannot reach final solution due to we tried each of the answers but they all fails.
    You don't solve the problem. :D 
    You just point out what is the problem and bring in new approaches when necessary. 

    You have to evaluate the test cases or the solution we have with one of the these three words: [CONTINUE], [DONE] or [STUCKED]
    The action of the words are: 
    - [DONE] : it means the task is successfully solved the test and the test was appropriate or you reached a state which actually means you solved the task.
    - [STUCKED] : it means you tried different approach or just too many but none is good enough to succeed with the tests and you actually need further assistant. 
    - [CONTINUE] : which means new iteration should be made to fulfill the test cases or your solution have to be improved or you have more idea on how to resolve the tests. 

    Given that these question were asked by us:
    $(ctx_question)

    The latest answer was this:
    $(new_ai_msg)

    and the shell results are:
    $(ctx_shell)

    and the test results are:
    $(ctx_test)
    """
    aigenerated = PromptingTools.aigenerate(prompt, model="claudeh", verbose=false) # gpt4om, claudeh
    return String(aigenerated.content)
end


LLM_reflect_condition(resp) = begin
    c=Condition(patterns=Dict{String,Symbol}(
        "[DONE]" => :DONE,
        "[STUCKED]" => :STUCKED,
    	"[CONTINUE]" => :CONTINUE,
    )); 
    c.response=parse(c, resp)
    !(c.response in [:DONE, :STUCKED, :CONTINUE]) && @warn "We couldn't identify direction! (maybe autostop with warning??)"
    c
end
is_continue(c::Condition) = c.response == :CONTINUE 