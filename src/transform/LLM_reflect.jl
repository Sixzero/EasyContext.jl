
using PromptingTools

export LLM_reflect, is_continue, LLM_reflect_condition

function LLM_reflect(ctx_question, ctx_shell, new_ai_msg)
    prompt = """
    You are an AI assistant specialized in criticizing and spotting problems with the solution and we want to reach ready [DONE] state or you have to detect if solution [STUCKED] and cannot reach final solution or [WAITING] for user feedback, otherwise we have to [CONTINUE] our work.
    You don't solve the problem you only have to spot the problem if there is any. 
    You just point out what is the problem and only say the must know things to resolve the problem nothing more if there is any problem.
    Be simple when reflecting and giving feedback.
    Be minimalistic and concise. 
    Focus on the main problem.

    To evaluate the solution you have to decide from the following 4 state: [DONE], [STUCKED], [WAITING], or [CONTINUE].
    The action of the words are: 
    - [DONE] : it means the task is successfully solved or you reached a state which actually means you solved the task. 
    - [STUCKED] : it means you tried different approach or just too many but none is good enough to succeed with the tests or anything else and you actually need further assistant.
    - [WAITING] : it means we need user information to proceed. 
    - [CONTINUE] : based on the results and feedback the problem can be solved, but the new feedback are necessary to be fulfilled or the solution have to be improved or you know it can be solved.

    Given that these question were asked by us:
    $(ctx_question)

    The latest answer was this:
    $(new_ai_msg)

    and the shell results are here:
    $(ctx_shell)
    """
    aigenerated = PromptingTools.aigenerate(prompt, model="claudeh", verbose=false, streamcallback=stdout) # gpt4om, claudeh
    return String(aigenerated.content)
end


LLM_reflect_condition(resp) = begin
    c=Condition(patterns=Dict{String,Symbol}(
        "[DONE]"     => :DONE,
        "[STUCKED]"  => :STUCKED,
        "[WAITING]"  => :WAITING,
    	"[CONTINUE]" => :CONTINUE,
    ));
    c.response=parse(c, resp)
    !(c.response in [:DONE, :STUCKED, :WAITING, :CONTINUE]) && @warn "We couldn't identify direction! (maybe autostop with warning??)"
    c
end
is_continue(c::Condition) = c.response == :CONTINUE 