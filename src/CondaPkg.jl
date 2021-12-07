module CondaPkg

import Base: @kwdef
import MicroMamba
import Pkg
import TOML

let toml = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    @eval const UUID = Base.UUID($(toml["uuid"]))
    @eval const PKGID = Base.PkgId(UUID, "CondaPkg")
    @eval const VERSION = Base.VersionNumber($(toml["version"]))
end

@kwdef mutable struct State
    resolved::Bool = false
    load_path::Vector{String} = String[]
    meta_dir::String = ""
end

const STATE = State()

@kwdef struct PkgSpec
    name::String
    version::String
    channels::Vector{String}
end

@kwdef mutable struct Meta
    timestamp::Float64
    load_path::Vector{String}
    extra_path::Vector{String}
    version::VersionNumber
    packages::Vector{PkgSpec}
end

const META_VERSION = 1 # increment whenever the metadata format changes

function read_meta(io::IO)
    if read(io, Int) == META_VERSION
        Meta(
            timestamp = read_meta(io, Float64),
            load_path = read_meta(io, Vector{String}),
            extra_path = read_meta(io, Vector{String}),
            version = read_meta(io, VersionNumber),
            packages = read_meta(io, Vector{PkgSpec}),
        )
    end
end
function read_meta(io::IO, ::Type{Float64})
    read(io, Float64)
end
function read_meta(io::IO, ::Type{String})
    len = read(io, Int)
    bytes = read(io, len)
    if length(bytes) < len
        error("unexpected end of meta file")
    end
    String(bytes)
end
function read_meta(io::IO, ::Type{Vector{T}}) where {T}
    len = read(io, Int)
    ans = Vector{T}()
    for _ in 1:len
        item = read_meta(io, T)
        push!(ans, item)
    end
    ans
end
function read_meta(io::IO, ::Type{VersionNumber})
    VersionNumber(read_meta(io, String))
end
function read_meta(io::IO, ::Type{PkgSpec})
    PkgSpec(
        name = read_meta(io, String),
        version = read_meta(io, String),
        channels = read_meta(io, Vector{String}),
    )
end

function write_meta(io::IO, meta::Meta)
    write(io, META_VERSION)
    write_meta(io, meta.timestamp)
    write_meta(io, meta.load_path)
    write_meta(io, meta.extra_path)
    write_meta(io, meta.version)
    write_meta(io, meta.packages)
    return
end
function write_meta(io::IO, x::Float64)
    write(io, x)
end
function write_meta(io::IO, x::String)
    write(io, convert(Int, sizeof(x)))
    write(io, x)
end
function write_meta(io::IO, x::Vector)
    write(io, convert(Int, length(x)))
    for item in x
        write_meta(io, item)
    end
end
function write_meta(io::IO, x::VersionNumber)
    write_meta(io, string(x))
end
function write_meta(io::IO, x::PkgSpec)
    write_meta(io, x.name)
    write_meta(io, x.version)
    write_meta(io, x.channels)
end

function resolve(; force::Bool=false)
    # skip resolving if already resolved and LOAD_PATH unchanged
    # this is a very fast check which avoids touching the file system
    load_path = Base.load_path()
    if !force && STATE.resolved && STATE.load_path == load_path
        return
    end
    STATE.resolved = false
    STATE.load_path = load_path
    # find the topmost env in the load_path which depends on CondaPkg
    top_env = ""
    for env in load_path
        proj = Base.env_project_file(env)
        is_condapkg = proj isa String && Base.project_file_name_uuid(proj, "").uuid == UUID
        depends_on_condapkg = Base.manifest_uuid_path(env, PKGID) !== nothing
        if is_condapkg || depends_on_condapkg
            top_env = proj isa String ? dirname(proj) : env
            break
        end
    end
    STATE.meta_dir = meta_dir = joinpath(top_env, ".CondaPkg")
    meta_file = joinpath(meta_dir, "meta")
    conda_env = joinpath(meta_dir, "env")
    # skip resolving if nothing has changed since the metadata was updated
    if isdir(conda_env) && isfile(meta_file)
        meta = open(read_meta, meta_file)
        if meta !== nothing && meta.version == VERSION && meta.load_path == load_path
            timestamp = max(meta.timestamp, stat(meta_file).mtime)
            skip = true
            for env in [meta.load_path; meta.extra_path]
                dir = isfile(env) ? dirname(env) : isdir(env) : env : continue
                if isdir(dir)
                    if stat(dir).mtime > timestamp
                        skip = false
                        break
                    else
                        fn = joinpath(dir, "CondaPkg.toml")
                        if isfile(fn) && stat(fn).mtime > timestamp
                            skip = false
                            break
                        end
                    end
                end
            end
            if skip
                STATE.resolved = true
                return
            end
        end
    end
    # find all dependencies
    packages = Dict{String,Dict{String,PkgSpec}}() # name -> depsfile -> spec
    extra_path = String[]
    for env in [load_path; [p.source for p in values(Pkg.dependencies())]]
        dir = isfile(env) ? dirname(env) : isdir(env) : env : continue
        fn = joinpath(dir, "CondaPkg.toml")
        if isfile(fn)
            env in load_path || push!(extra_path, env)
            toml = TOML.parsefile(fn)
            channels = ["conda-forge"]
            if haskey(toml, "deps")
                deps = toml["deps"]
                deps isa Dict || error("deps must be a table")
                for (name, spec) in deps
                    name isa String || error("deps key must be a string")
                    if spec isa String
                        pspec = PkgSpec(name=name, version=strip(spec), channels=channels)
                    else
                        error("deps value must be a string (for now)")
                    end
                    get!(Dict{String,PkgSpec}, packages, name)[fn] = pspec
                end
            end
        end
    end
    # merge dependencies
    specs = PkgSpec[]
    for (name, pkgs) in packages
        @assert length(pkgs) > 0
        @assert all(pkg.name == name for pkg in values(pkgs))
        version = join([pkg.version for pkg in values(pkgs) if pkg.version != ""], ",")
        channels = String[]
        for pkg in values(pkgs)
            if isempty(channels)
                append!(channels, pkg.channels)
            else
                intersect!(channels, pkg.channels)
                if isempty(channels)
                    lines = ["inconsistent channel specifications:"]
                    for (fn, pkg) in pkgs
                        push!(lines, "- $fn: $(join(pkg.channels, ", ", " or "))")
                    end
                end
            end
        end
        push!(specs, PkgSpec(name=name, version=version, channels=sort(channels)))
    end
    # skip any conda calls if the dependencies haven't changed
    if isfile(meta_file) && isdir(conda_env)
        meta = open(read_meta, meta_file)
        if meta !== nothing && meta.packages == specs && stat(conda_env).mtime < meta.timestamp
            @goto save_meta
        end
    end
    # group dependencies by channels
    gspecs = Dict{Vector{String},Vector{PkgSpec}}()
    for spec in specs
        push!(get!(Vector{PkgSpec}, gspecs, spec.channels), spec)
    end
    # remove and recreate any existing conda environment
    mkpath(meta_dir)
    if isdir(conda_env)
        cmd = MicroMamba.cmd(`remove -y -q -p $conda_env --all`)
        @info "Removing Conda environment" cmd
        run(cmd)
    end
    cmd = MicroMamba.cmd(`create -y -q -p $conda_env`)
    @info "Creating Conda environment" cmd
    run(cmd)
    for (channels, specs) in gspecs
        args = String[]
        for spec in specs
            if spec.version == ""
                push!(args, spec.name)
            else
                push!(args, "$(spec.name) $(spec.version)")
            end
        end
        for channel in channels
            push!(args, "-c", channel)
        end
        cmd = MicroMamba.cmd(`install -y -q -p $conda_env $args`)
        @info "Installing Conda packages" cmd
        run(cmd)
    end
    # save metadata
    @label save_meta
    meta = Meta(
        timestamp = time(),
        load_path = load_path,
        extra_path = extra_path,
        version = VERSION,
        packages = specs,
    )
    open(io->write_meta(io, meta), meta_file, "w")
    # all done
    STATE.resolved = true
    return
end

"""
    env()

Return the path to the Conda environment.
"""
function env()
    resolve()
    joinpath(STATE.meta_dir, "env")
end

function shell(cmd)
    if Sys.iswindows()
        shell = "powershell"
        exportvarregex = r"^\$Env:([^ =]+) *= *\"(.*)\"$"
        setvarregex = exportvarregex
        unsetvarregex = r"^(Remove-Item +\$Env:/|Remove-Variable +)([^ =]+)$"
        runscriptregex = r"^\. +\"(.*)\"$"
    else
        shell = "posix"
        exportvarregex = r"^\\?export ([^ =]+)='(.*)'$"
        setvarregex = r"^([^ =]+)='(.*)'"
        unsetvarregex = r"^\\?unset +([^ ]+)$"
        runscriptregex = r"^\\?\. +\"(.*)\"$"
    end
    for line in eachline(MicroMamba.cmd(`shell -s $shell $cmd -p $(env())`))
        if (m = match(exportvarregex, line)) !== nothing
            @debug "Setting environment" key=m.captures[1] value=m.captures[2]
            ENV[m.captures[1]] = m.captures[2]
        elseif (m = match(unsetvarregex, line)) !== nothing
            @debug "Deleting environment" key=m.captures[1]
            delete!(ENV, m.captures[1])
        else
            @debug "Ignoring shell $cmd line" line
        end
    end
end

"""
    withenv(f::Function)

Call `f()` while the Conda environment is active.
"""
function withenv(f::Function)
    old_env = copy(ENV)
    shell("activate")
    try
        return f(joinpath(STATE.meta_dir, "env"))
    finally
        for k in collect(keys(ENV))
            if !haskey(old_env, k)
                delete!(ENV, k)
            end
        end
        for (k, v) in old_env
            ENV[k] = v
        end
    end
end

end # module
