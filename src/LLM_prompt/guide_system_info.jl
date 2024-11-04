get_system() = strip(read(`uname -a`, String))
get_shell() = strip(read(`$(ENV["SHELL"]) --version`, String))

const system_information = """
The system is:
$(get_system())
The used SHELL is:
$(get_shell())
The SHELL is in this folder right now:
$(home_abrev(pwd()))
"""