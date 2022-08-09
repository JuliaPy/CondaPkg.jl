module CondaPkg

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@compiler_options"))
    # Without this, resolve() takes a couple of seconds, with, it takes 0.1 seconds.
    # Maybe with better structured code or precompilation it's not necessary.
    # Note: compile=min makes --code-coverage not work
    @eval Base.Experimental.@compiler_options optimize=0 infer=false #compile=min
end

import Base: @kwdef
import MicroMamba
import JSON3
import Pidfile
import Pkg
import TOML

let toml = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    @eval const UUID = Base.UUID($(toml["uuid"]))
    @eval const PKGID = Base.PkgId(UUID, "CondaPkg")
    @eval const VERSION = Base.VersionNumber($(toml["version"]))
end

@kwdef mutable struct State
    # backend
    backend::Symbol = :NotSet
    condaexe::String = ""
    # resolve
    resolved::Bool = false
    load_path::Vector{String} = String[]
    meta_dir::String = ""
    frozen::Bool = false
end

const STATE = State()

include("backend.jl")
include("spec.jl")
include("meta.jl")
include("resolve.jl")
include("env.jl")
include("deps.jl")

include("PkgREPL.jl")

end # module
