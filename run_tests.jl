using Pkg

# Activate the project environment
Pkg.activate(".")

# Instantiate the environment (install dependencies)
Pkg.instantiate()

# Run the tests
Pkg.test()
