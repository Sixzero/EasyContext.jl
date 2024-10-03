doc = join(["really long text over 8000 token" for i in 1:1000], "\n")
msg = RAG.aiembed(doc; verbose = true)
