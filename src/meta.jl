"""
This file defines functions to interact with the `.CondaPkg/meta` file which records
information about the most recent resolve.
"""

# increment whenever the metadata format changes
const META_VERSION = 11

@kwdef mutable struct Meta
    timestamp::Float64
    conda_env::String
    load_path::Vector{String}
    extra_path::Vector{String}
    version::VersionNumber
    packages::Vector{PkgSpec}
    channels::Vector{ChannelSpec}
    pip_packages::Vector{PipPkgSpec}
    temp_packages::Dict{String,Dict{String,PkgSpec}}
    temp_channels::Dict{String,Dict{String,ChannelSpec}}
    temp_pip_packages::Dict{String,Dict{String,PipPkgSpec}}
end

function read_meta(io::IO)
    # TODO: magic number?
    if read(io, Int) == META_VERSION
        Meta(
            timestamp = read_meta(io, Float64),
            conda_env = read_meta(io, String),
            load_path = read_meta(io, Vector{String}),
            extra_path = read_meta(io, Vector{String}),
            version = read_meta(io, VersionNumber),
            packages = read_meta(io, Vector{PkgSpec}),
            channels = read_meta(io, Vector{ChannelSpec}),
            pip_packages = read_meta(io, Vector{PipPkgSpec}),
            temp_packages = read_meta(io, Dict{String,Dict{String,PkgSpec}}),
            temp_channels = read_meta(io, Dict{String,Dict{String,ChannelSpec}}),
            temp_pip_packages = read_meta(io, Dict{String,Dict{String,PipPkgSpec}}),
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
function read_meta(io::IO, ::Type{Dict{K,V}}) where {K,V}
    len = read(io, Int)
    ans = Dict{K,V}()
    for _ in 1:len
        k = read_meta(io, K)
        v = read_meta(io, V)
        ans[k] = v
    end
    ans
end
function read_meta(io::IO, ::Type{VersionNumber})
    VersionNumber(read_meta(io, String))
end
function read_meta(io::IO, ::Type{PkgSpec})
    name = read_meta(io, String)
    version = read_meta(io, String)
    channel = read_meta(io, String)
    build = read_meta(io, String)
    PkgSpec(name, version=version, channel=channel, build=build)
end
function read_meta(io::IO, ::Type{ChannelSpec})
    name = read_meta(io, String)
    ChannelSpec(name)
end
function read_meta(io::IO, ::Type{PipPkgSpec})
    name = read_meta(io, String)
    version = read_meta(io, String)
    binary = read_meta(io, String)
    PipPkgSpec(name, version=version, binary=binary)
end

function write_meta(io::IO, meta::Meta)
    write(io, META_VERSION)
    write_meta(io, meta.timestamp)
    write_meta(io, meta.conda_env)
    write_meta(io, meta.load_path)
    write_meta(io, meta.extra_path)
    write_meta(io, meta.version)
    write_meta(io, meta.packages)
    write_meta(io, meta.channels)
    write_meta(io, meta.pip_packages)
    write_meta(io, meta.temp_packages)
    write_meta(io, meta.temp_channels)
    write_meta(io, meta.temp_pip_packages)
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
function write_meta(io::IO, x::Dict)
    write(io, convert(Int, length(x)))
    for (k, v) in x
        write_meta(io, k)
        write_meta(io, v)
    end
end
function write_meta(io::IO, x::VersionNumber)
    write_meta(io, string(x))
end
function write_meta(io::IO, x::PkgSpec)
    write_meta(io, x.name)
    write_meta(io, x.version)
    write_meta(io, x.channel)
    write_meta(io, x.build)
end
function write_meta(io::IO, x::ChannelSpec)
    write_meta(io, x.name)
end
function write_meta(io::IO, x::PipPkgSpec)
    write_meta(io, x.name)
    write_meta(io, x.version)
    write_meta(io, x.binary)
end
