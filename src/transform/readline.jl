using REPL

dialog() = print("\e[36m➜ \e[0m")  # teal arrow

function readline_multi()
    buffer = IOBuffer()
    empty_lines = 0
    while true
        batch = readavailable(stdin)
        if length(batch) == 1 && batch[1] == 0x0a  # newline character
            empty_lines += 1
            if empty_lines == 2
                break
            end
        else
            empty_lines = 0
        end
        write(buffer, batch)
    end
    return String(take!(buffer))
end

function readline_multi_interactive()
    buffer = IOBuffer()
    empty_lines = 0
    while true
        char = read(stdin, Char)
        if char in ('\n', '\r')
            empty_lines += 1
            if empty_lines == 3
                break
            end
        elseif !isspace(char)
            empty_lines = 0
        end
        write(buffer, char)
        print(char)
    end
    return String(take!(buffer))
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

function wait_user_question(user_question)
    while is_really_empty(user_question)
        user_question = readline_improved()
    end
    user_question
end
