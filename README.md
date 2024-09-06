# EasyContext.jl

EasyContext.jl is a Julia package that enhances the context-aware capabilities of AI-powered applications. It provides tools for efficient document indexing, embedding, and retrieval, making it easier to build robust Retrieval-Augmented Generation (RAG) systems.

## Features

- **Flexible Embedding Options**: Supports multiple embedding models, including Jina AI's embedding services.
- **Efficient Indexing**: Utilizes various indexing strategies for quick and relevant information retrieval.
- **Advanced Retrieval**: Implements sophisticated retrieval methods, including cosine similarity and BM25.
- **Context-Aware Processing**: Provides context processors for different types of information sources, such as codebase files and Julia packages.
- **Customizable RAG Pipeline**: Offers a configurable RAG system with interchangeable components for indexing, retrieval, and generation.

## Installation

To install EasyContext.jl, use the Julia package manager:

```julia
using Pkg
Pkg.add("EasyContext")
```

## Usage

Here's a basic example of how to use EasyContext.jl:

```julia
using EasyContext
using PromptingTools

# Initialize the RAG configuration
rag_conf, rag_kwargs = get_rag_config()

# Build or load the index
index = build_installed_package_index()

# Use the RAG system to answer a question
question = "How do I use DifferentialEquations.jl to solve an ODE?"
result = get_answer(question; index=index, rag_conf=rag_conf)

println(result.content)
```

## Main Components

1. **JinaEmbedder**: A struct for embedding documents using Jina AI's embedding models.
2. **FullFileChunker**: A chunker that processes entire files as single chunks.
3. **GolemSourceChunker**: A specialized chunker for Julia source code.
4. **ReduceRankGPTReranker**: A reranker that uses GPT models to improve retrieval results.
5. **Various Context Processors**: Including CodebaseContext, ShellContext, and JuliaPackageContext.

## Advanced Features

- **Multi-Index Support**: Combine different indexing strategies for more comprehensive retrieval.
- **Asynchronous Processing**: Utilize Julia's multi-threading capabilities for faster embedding and retrieval.
- **Caching**: Implement caching mechanisms to speed up repeated queries and reduce API calls.

## Contributing

Contributions to EasyContext.jl are welcome! Please feel free to submit issues, feature requests, or pull requests on our GitHub repository.

## License

EasyContext.jl is released under the MIT License. See the LICENSE file in the project repository for more details.

