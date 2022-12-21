using TestItemRunner

# start with a clean state
pop!(ENV, "MAMBA_ROOT_PREFIX", nothing)
pop!(ENV, "JULIA_CONDAPKG_LIBSTDCXX_VERSION_BOUND", nothing)
pop!(ENV, "JULIA_CONDAPKG_VERBOSITY", nothing)
pop!(ENV, "JULIA_CONDAPKG_BACKEND", nothing)
pop!(ENV, "JULIA_CONDAPKG_OFFLINE", nothing)
pop!(ENV, "JULIA_CONDAPKG_EXE", nothing)
pop!(ENV, "JULIA_CONDAPKG_ENV", nothing)

# avoid micromamba flooding the terminal with progress bar characters
get!(ENV, "CI", true)

@run_package_tests
