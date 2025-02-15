export get_user_confirmation
using DingDingDing

function notify_user()
    if !Sys.isapple()  # Skip notification on macOS
        DingDingDing.play(DingDingDing.rand_sound_file(DingDingDing.ding_files))
    end
end

function get_user_confirmation()
    notify_user()
    print("\e[34mContinue? (y) \e[0m")
    readchomp(`zsh -c "read -q '?'; echo \$?"`) == "0"
end