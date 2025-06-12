get_system() = strip(read(`uname -a`, String))
get_shell() = strip(read(`$(ENV["SHELL"]) --version`, String))

const system_information = """
"""