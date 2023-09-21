using TestItemRunner

# NOTE: use CI=true env var to avoid micromamba
# flooding the terminal with progress bar characters

if get(ENV, "CI", "false") == "false"
    @info "local tests"
    # start with a clean state when running local tests
    delete!(ENV, "MAMBA_ROOT_PREFIX")
    delete!(ENV, "JULIA_CONDAPKG_VERBOSITY")
    delete!(ENV, "JULIA_CONDAPKG_BACKEND")
    delete!(ENV, "JULIA_CONDAPKG_OFFLINE")
    delete!(ENV, "JULIA_CONDAPKG_EXE")
    delete!(ENV, "JULIA_CONDAPKG_ENV")
end

@run_package_tests
