module CondaPkg

if isdefined(Base, :Experimental) &&
   isdefined(Base.Experimental, Symbol("@compiler_options"))
    # Without this, resolve() takes a couple of seconds, with, it takes 0.1 seconds.
    # Maybe with better structured code or precompilation it's not necessary.
    # Note: compile=min makes --code-coverage not work
    @eval Base.Experimental.@compiler_options optimize = 0 infer = false #compile=min
end

using Base: @kwdef
using JSON3: JSON3
using Pidfile: Pidfile
using Preferences: @load_preference
using Pkg: Pkg
using Scratch: @get_scratch!
using TOML: TOML

# these are loaded lazily to avoid downloading the JLLs unless they are needed
MICROMAMBA_MODULE = Ref{Module}()
PIXI_JLL_MODULE = Ref{Module}()

function micromamba_module()
    if !isassigned(MICROMAMBA_MODULE)
        MICROMAMBA_MODULE[] = Base.require(CondaPkg, :MicroMamba)
    end
    MICROMAMBA_MODULE[]
end

function pixi_jll_module()
    if !isassigned(PIXI_JLL_MODULE)
        PIXI_JLL_MODULE[] = Base.require(CondaPkg, :pixi_jll)
    end
    PIXI_JLL_MODULE[]
end

let toml = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    @eval const UUID = Base.UUID($(toml["uuid"]))
    @eval const PKGID = Base.PkgId(UUID, "CondaPkg")
    @eval const VERSION = Base.VersionNumber($(toml["version"]))
end

@kwdef mutable struct State
    # backend
    backend::Symbol = :NotSet
    condaexe::String = ""
    pixiexe::String = ""
    # resolve
    resolved::Bool = false
    load_path::Vector{String} = String[]
    meta_dir::String = ""
    conda_env::String = ""
    shared::Bool = false
    frozen::Bool = false
end

const STATE = State()

function getpref(::Type{T}, prefname, envname, default = nothing) where {T}
    ans = @load_preference(prefname, nothing)
    ans === nothing || return checkpref(T, ans)::T
    ans = get(ENV, envname, "")
    isempty(ans) || return checkpref(T, ans)::T
    return default
end

checkpref(::Type{T}, x) where {T} = convert(T, x)
checkpref(::Type{String}, x::AbstractString) = convert(String, x)
checkpref(::Type{T}, x::AbstractString) where {T} = parse(T, x)
checkpref(::Type{Bool}, x::AbstractString) =
    x in ("yes", "true") ? true :
    x in ("no", "false") ? false : error("expecting true or false, got $(repr(x))")

include("backend.jl")
include("spec.jl")
include("meta.jl")
include("resolve.jl")
include("env.jl")
include("deps.jl")

include("PkgREPL.jl")

end # module
