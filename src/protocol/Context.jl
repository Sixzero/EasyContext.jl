mutable struct Context{T}
	d::OrderedDict{String, T}
end

# TODO limit T to Union{<:AbstractChunk, String}
Context{T}() where T = Context{T}(OrderedDict{String, T}())
Context(chunks::AbstractVector{T}) where T = Context{T}(OrderedDict{String, T}(get_source(v) => v for v in chunks))

Base.merge!(ctx::Context, new_ctx::Context) = merge!(ctx, new_ctx.d)
Base.merge!(ctx::Context, new_ctx::AbstractVector{T}) where T = (merge!(ctx, Context(new_ctx));   return ctx)
Base.merge!(ctx::Context, new_ctx::AbstractDict{String, T}) where T = (merge!(ctx.d, new_ctx);   return ctx)

Base.length(ctx::Context) = length(ctx.d)


# python_format_description()     = "\
# The Python packages in other existing installed packages will be in the user message and \
# wrapped in <$(PYTHON_TAG)> and </$(PYTHON_TAG)> tags, \
# with individual chunks wrapped in <$(PYTHON_ELEMENT)> and </$(PYTHON_ELEMENT)> tags."
# test_format_description(t)      = """
# We have a buildin testframework which has a testfile: $(t.filepath) 
# We run the test file: $(t.run_test_command) 
# To create tests that runs automatically, you have to modify the testfile: $(t.filepath) 
# The test code is wrapped in <$(TEST_CODE)> and </$(TEST_CODE)> tags, 
# Each run results of test_code run is wrapped in <$(TEST_RESULT) sh="$(t.run_test_command)"> and </$(TEST_RESULT)> tags where the sh property is the way we run the test file.
# """


# If you find the default test run command not appropriate then you can propose another one like: 

