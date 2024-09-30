using REPL

dialog() = print("\e[36m➜ \e[0m")  # teal arrow

function readline_multi()
    buffer = IOBuffer()
    while true
        batch = readavailable(stdin)
        length(batch) == 1 && batch[1] == 0x0a && break
        write(buffer, batch)
    end
    return String(take!(buffer))
end

function readline_multi_interactive()
    buffer = IOBuffer()
    newlines = 0
    while true
        char = read(stdin, Char)
        write(buffer, char)
        print(char)
        if char in ('\n', '\r')
            newlines += 1
            newlines == 2 && return String(take!(buffer))
        else
            newlines = 0
        end
    end
end


function readline_improved()
    dialog()
    print("\e[1m")  # bold text
    if isinteractive()
        res = readline_multi_interactive()
    else
        res = readline_multi()
    end
    clearline()
    clearline()
    print("\e[0m")  # reset text style
    return res
end

wait_user_question(user_question) = begin
    while is_really_empty(user_question)
        user_question = readline_improved()
    end
    user_question
end