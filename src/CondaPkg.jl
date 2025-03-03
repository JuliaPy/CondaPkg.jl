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
const MICROMAMBA_MODULE = Ref{Module}()
const PIXI_JLL_MODULE = Ref{Module}()

const MICROMAMBA_PKGID =
    Base.PkgId(Base.UUID("0b3b1443-0f03-428d-bdfb-f27f9c1191ea"), "MicroMamba")
const PIXI_JLL_PKGID =
    Base.PkgId(Base.UUID("4d7b5844-a134-5dcd-ac86-c8f19cd51bed"), "pixi_jll")

function micromamba_module()
    if !isassigned(MICROMAMBA_MODULE)
        MICROMAMBA_MODULE[] = Base.require(MICROMAMBA_PKGID)
    end
    MICROMAMBA_MODULE[]
end

function pixi_jll_module()
    if !isassigned(PIXI_JLL_MODULE)
        PIXI_JLL_MODULE[] = Base.require(PIXI_JLL_PKGID)
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
    # testing
    testing::Bool = false
    test_preferences::Dict{String,Any} = Dict{String,Any}()
end

const STATE = State()

function getpref(::Type{T}, prefname, envname, default = nothing) where {T}
    if STATE.testing
        ans = get(STATE.test_preferences, prefname, nothing)
        ans === nothing || return checkpref(T, ans)::T
        return default
    end
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
checkpref(::Type{Vector{String}}, x::AbstractString) = collect(String, split(x))
checkpref(::Type{Dict{String,String}}, x::AbstractString) =
    checkpref(Dict{String,String}, split(x))
checkpref(::Type{Pair{String,String}}, x::AbstractString) =
    let (x1, x2) = split(x, "->", limit = 2)
        Pair{String,String}(x1, x2)
    end
checkpref(::Type{Dict{String,String}}, x::AbstractVector) =
    Dict{String,String}(checkpref(Pair{String,String}, p) for p in x)

# Specific preference functions
getpref_backend() = getpref(String, "backend", "JULIA_CONDAPKG_BACKEND", "")
getpref_exe() = getpref(String, "exe", "JULIA_CONDAPKG_EXE", "")
getpref_env() = getpref(String, "env", "JULIA_CONDAPKG_ENV", "")
getpref_libstdcxx_ng_version() =
    getpref(String, "libstdcxx_ng_version", "JULIA_CONDAPKG_LIBSTDCXX_NG_VERSION", "")
getpref_openssl_version() =
    getpref(String, "openssl_version", "JULIA_CONDAPKG_OPENSSL_VERSION", "")
getpref_verbosity() = getpref(Int, "verbosity", "JULIA_CONDAPKG_VERBOSITY", 0)
getpref_offline() = getpref(Bool, "offline", "JULIA_CONDAPKG_OFFLINE", false)

function getpref_channel_priority()
    p = getpref(String, "channel_priority", "JULIA_CONDAPKG_CHANNEL_PRIORITY", "flexible")
    if p in ("strict", "flexible", "disabled")
        return p
    else
        error("channel_priority must be strict, flexible or disabled, got $p")
    end
end

function getpref_channel_order()
    order =
        getpref(Vector{String}, "channel_order", "JULIA_CONDAPKG_CHANNEL_ORDER", String[])
    String[c == "..." ? c : validate_channel(c) for c in order]
end

function getpref_pip_backend()
    b = getpref(String, "pip_backend", "JULIA_CONDAPKG_PIP_BACKEND", "uv")
    if b == "pip"
        :pip
    elseif b == "uv"
        :uv
    else
        error("pip_backend must be pip or uv, got $b")
    end
end

function getpref_allowed_channels()
    channels = getpref(
        Vector{String},
        "allowed_channels",
        "JULIA_CONDAPKG_ALLOWED_CHANNELS",
        nothing,
    )
    if channels === nothing
        nothing
    else
        Set{String}(validate_channel(c) for c in channels)
    end
end

function getpref_channel_mapping()
    mapping = getpref(
        Dict{String,String},
        "channel_mapping",
        "JULIA_CONDAPKG_CHANNEL_MAPPING",
        Dict{String,String}(),
    )

    # Validate all channel names
    validated = Dict{String,String}()
    for (old, new) in mapping
        old_validated = validate_channel(old)
        new_validated = validate_channel(new)
        validated[old_validated] = new_validated
    end

    validated
end

include("backend.jl")
include("spec.jl")
include("meta.jl")
include("resolve.jl")
include("env.jl")
include("deps.jl")

include("PkgREPL.jl")

end # module
