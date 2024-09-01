using PromptingTools
using PromptingTools.Experimental.RAGTools
using LinearAlgebra, SparseArrays
using PromptingTools.Experimental.RAGTools: SimpleIndexer

sentences = [
    "Find the most comprehensive guide on Julia programming language for beginners published in 2023.",
    "Search for the latest advancements in quantum computing using Julia language.",
    "How to implement machine learning algorithms in Julia with examples.",
    "Looking for performance comparison between Julia, Python, and R for data analysis.",
    "Find Julia language tutorials focusing on high-performance scientific computing.",
    "Search for the top Julia language packages for data visualization and their documentation.",
    "How to set up a Julia development environment on Windows 10.",
    "Discover the best practices for parallel computing in Julia.",
    "Search for case studies of large-scale data processing using Julia.",
    "Find comprehensive resources for mastering metaprogramming in Julia.",
    "Looking for articles on the advantages of using Julia for statistical modeling.",
    "How to contribute to the Julia open-source community: A step-by-step guide.",
    "Find the comparison of numerical accuracy between Julia and MATLAB.",
    "Looking for the latest Julia language updates and their impact on AI research.",
    "How to efficiently handle big data with Julia: Techniques and libraries.",
    "Discover how Julia integrates with other programming languages and tools.",
    "Search for Julia-based frameworks for developing web applications.",
    "Find tutorials on creating interactive dashboards with Julia.",
    "How to use Julia for natural language processing and text analysis.",
    "Discover the role of Julia in the future of computational finance and econometrics."
]

indexer = SimpleIndexer()
index = build_index(indexer, sentences; chunker_kwargs=(; sources=map(i -> "Sentence$i", 1:length(sentences))))

#%%
using PromptingTools.Experimental.RAGTools
PTER = PromptingTools.Experimental.RAGTools
struct CodeChunker <: PTER.AbstractChunker end
indexer = SimpleIndexer(;chunker=CodeChunker())
index = build_index(indexer, sentences; chunker_kwargs=(; sources=map(i -> "Sentence$i", 1:length(sentences))))
#%%
question = "What are the best practices for parallel computing in Julia?"

msg = airag(index; question)
#%%
result = airag(index; question, return_all=true)
#%%
result.sources
#%%
# Retrieve which chunks are relevant to the question
returns = retrieve(index, question)

# Generate an answer
result = generate!(index, returns)
#%%
using PromptingTools
using CodeTracking
function walk_include_graph(pkg_name::String)
    files = CodeTracking.pkgfiles(pkg_name)
    @show (files)
    include_graph = Dict{String, Vector{Pair{Module, String}}}()
    
    for file_end in files.files
        file = joinpath(files.basedir, file_end)
        mexs = Revise.parse_source(file, Main)
        if mexs !== nothing
            for (mod, exprs) in mexs
                @show exprs
                include_calls = filter(ex -> ex.head == :call && ex.args[1] in (:include, :includet), exprs)
                include_graph[file] = [(mod => String(inc.args[2])) for inc in include_calls]
            end
        end
    end
    
    return include_graph
end
walk_include_graph("PromptingTools")
#%%
@show returns
#%%
pprint(result)
#%%
returns = retrieve(index, question)
@show returns
#%%
using PromptingTools
aigenerate("How could I iterate over all the files and modules in my installed julia environment? Also I want all the Pkg.dev installed modules too!", model="claude")


#%%

aigenerate("How could I iterate over all the files and modules in my installed julia environment? Also I want all the Pkg.dev installed modules too!", model="deepseek-coder")
#%%
PT = PromptingTools
PT.registry["deepseek-coder"]
#%%
using Pkg
using FilePaths

# List all installed packages
installed_packages = Pkg.installed()

# Function to iterate over files in a package
function list_package_files(package_name)
  @show package_name
    # Get the package path
    pkg_path = Pkg.pkg"$(package_name)".path
    # List all files in the package directory
    return readdir(pkg_path, join=true)
end

# Iterate over installed packages and list their files
for (pkg_name, p) in installed_packages
    println("Files for package: $pkg_name")
    files = list_package_files(pkg_name)
    for file in files
        println(file)
    end
end

# Iterate over development packages and list their files
for (pkg_name, _) in dev_packages
    println("Files for dev package: $pkg_name")
    files = list_package_files(pkg_name)
    for file in files
        println(file)
    end
end
#%%
using PromptingTools.Experimental.RAGTools: OpenTagger, NoTagger, get_tags
using LinearAlgebra, SparseArrays
# Create an instance of OpenTagger
tagger = NoTagger()
tagger = OpenTagger()

# Define a vector of documents
docs = ["This is the first document.", "Here is another document."]

# Extract tags
tags = get_tags(tagger, sentences, verbose=true)

#%%
indexer = @edit SimpleIndexer()
indexer = SimpleIndexer()
build_index(indexer, sentences; chunker_kwargs=(; sources=map(i -> "Sentence$i", 1:length(sentences))))
# @edit Pkg.add("Plots")
# @edit sum(randn(10))
#%%
embeddings = RAG.get_embeddings(rag_conf.retriever.embedder, rephrased_questions;
verbose = true, cost_tracker, )