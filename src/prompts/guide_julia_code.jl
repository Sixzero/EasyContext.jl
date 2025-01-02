const julia_specific_guide = """
Please make sure if you use the \$ in the string and you want the dollar mark then you have to escape it or else it will be interpolated in the string literal ("").
The regex match return with SubString a strip(...) also return with SubString, so converted every SubString to String or write <:AbstractString or no type annotation to function to write correct code!
Always try to prefer oneliner solutions if possible! Shorter more descriptive is always better! 
We prefer @kwdef julia structs over constructors.
If we wrote tests or tried to fix test cases then in the end also try to run the tests.
Also when writing julia functions, try to use the oneliner format too like:
`foo() = "oneliner"`

Don't force type annotations. No type annotations for function headers from now!

"""
# Don't provide examples! 
# Don't annotate the function arguments with types. 
# """