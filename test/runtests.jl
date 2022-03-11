using CondaPkg
using Test

# Only run the gc tests on CI (because it's annoying to do it locally)
testgc = get(ENV, "CI", "") == "true"


status() = sprint(io -> CondaPkg.status(io=io))

backend = get(ENV, "JULIA_CONDAPKG_BACKEND", "MicroMamba")

backend == "MicroMamba" && include("micromamba.jl")
backend == "Null" && include("null.jl")
