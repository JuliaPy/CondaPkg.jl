"""
This file defines the types `PkgSpec`, `ChannelSpec` and `PipPkgSpec`, plus related
validation and normalisation functions.
"""

is_valid_string(name; allow_regex = false, allow_glob = false) =
    ('\'' ∉ name) &&
    ('"' ∉ name) &&
    (allow_regex || !(startswith(name, "^") && endswith(name, "\$"))) &&
    (allow_glob || '*' ∉ name)

struct PkgSpec
    name::String
    version::String
    channel::String
    build::String
    function PkgSpec(name; version = "", channel = "", build = "")
        name = validate_pkg(name)
        version = validate_version(version)
        channel = validate_channel(channel, allow_empty = true)
        build = validate_build(build)
        new(name, version, channel, build)
    end
end

# return a modified version of the given spec
function PkgSpec(
    old::PkgSpec;
    name = old.name,
    version = old.version,
    channel = old.channel,
    build = old.build,
)
    return PkgSpec(name; version, channel, build)
end

Base.:(==)(x::PkgSpec, y::PkgSpec) =
    (x.name == y.name) &&
    (x.version == y.version) &&
    (x.channel == y.channel) &&
    (x.build == y.build)
Base.hash(x::PkgSpec, h::UInt) =
    hash(x.build, hash(x.channel, hash(x.version, hash(x.name, h))))

is_valid_pkg(name) = occursin(r"^\s*[-_.a-zA-Z0-9]+\s*$", name) && is_valid_string(name)

normalise_pkg(name) = lowercase(strip(name))

validate_pkg(name) =
    if is_valid_pkg(name)
        normalise_pkg(name)
    else
        error("invalid package: $(repr(name))")
    end

is_valid_version(ver) =
    occursin(r"^\s*($|[!<>=0-9])", ver) && is_valid_string(ver; allow_glob = true)

normalise_version(ver) = strip(ver)

validate_version(ver) =
    if is_valid_version(ver)
        normalise_version(ver)
    else
        error("invalid version: $(repr(ver))")
    end

is_valid_build(build) = !occursin(''', build)

normalise_build(build) = strip(build)

validate_build(build) =
    if is_valid_build(build)
        return normalise_build(build)
    else
        error("invalid build: $(repr(build))")
    end

function specstr(x::PkgSpec)
    parts = String[]
    # always include the version, working around a bug in micromamba that the build is
    # ignored if the version is not set at all
    push!(parts, "version='$(x.version == "" ? "*" : x.version)'")
    x.channel == "" || push!(parts, "channel='$(x.channel)'")
    x.build == "" || push!(parts, "build='$(x.build)'")
    suffix = isempty(parts) ? "" : string("[", join(parts, ","), "]")
    string(x.name, suffix)
end

function pixispec(x::PkgSpec)
    spec = Dict{String,Any}()
    spec["version"] = x.version == "" ? "*" : x.version
    if x.build != ""
        spec["build"] = x.build
    end
    if x.channel != ""
        spec["channel"] = x.channel
    end
    if length(spec) == 1
        spec["version"]
    else
        spec
    end
end

struct ChannelSpec
    name::String
    function ChannelSpec(name)
        name = validate_channel(name)
        new(name)
    end
end

Base.:(==)(x::ChannelSpec, y::ChannelSpec) = (x.name == y.name)
Base.hash(x::ChannelSpec, h::UInt) = hash(x.name, h)

is_valid_channel(name; allow_empty = false) =
    (allow_empty || !isempty(strip(name))) && is_valid_string(name)

normalise_channel(name) = strip(name)

validate_channel(name; opts...) =
    if is_valid_channel(name; opts...)
        normalise_channel(name)
    else
        error("invalid channel: $(repr(name))")
    end

specstr(x::ChannelSpec) = x.name

struct PipPkgSpec
    name::String
    version::String
    binary::String
    extras::Vector{String}
    function PipPkgSpec(name; version = "", binary = "", extras = String[])
        name = validate_pip_pkg(name)
        version = validate_pip_version(version)
        binary = validate_pip_binary(binary)
        extras = validate_pip_extras(extras)
        new(name, version, binary, extras)
    end
end

Base.:(==)(x::PipPkgSpec, y::PipPkgSpec) =
    (x.name == y.name) &&
    (x.version == y.version) &&
    (x.binary == y.binary) &&
    (x.extras == y.extras)
Base.hash(x::PipPkgSpec, h::UInt) =
    hash(x.extras, hash(x.binary, hash(x.version, hash(x.name, h))))

is_valid_pip_pkg(name) = occursin(r"^\s*[-_.A-Za-z0-9]+\s*$", name)

normalise_pip_pkg(name) = replace(lowercase(strip(name)), r"[-._]+" => "-")

validate_pip_pkg(name) =
    if is_valid_pip_pkg(name)
        normalise_pip_pkg(name)
    else
        error("invalid pip package: $(repr(name))")
    end

is_valid_pip_version(ver) = occursin(r"^\s*($|[~!<>=@])", ver) && !occursin(";", ver)

normalise_pip_version(ver) = strip(ver)

validate_pip_version(ver) =
    if is_valid_pip_version(ver)
        normalise_pip_version(ver)
    else
        error("invalid pip version: $(repr(ver))")
    end

is_valid_pip_binary(x) = x in ("only", "no", "")

normalise_pip_binary(x) = x

validate_pip_binary(x) =
    if is_valid_pip_binary(x)
        return normalise_pip_binary(x)
    else
        error("invalid pip binary: $(repr(x)) (expecting \"only\" or \"no\")")
    end

validate_pip_extras(x) = sort!(unique!(map(validate_pip_extra, convert(Vector{String}, x))))

is_valid_pip_extra(x) = is_valid_pip_pkg(x)

normalise_pip_extra(x) = normalise_pip_pkg(x)

validate_pip_extra(x) =
    if is_valid_pip_extra(x)
        return normalise_pip_extra(x)
    else
        error("invalid pip extra: $(repr(x))")
    end

function specstr(x::PipPkgSpec)
    parts = String[x.name]
    if !isempty(x.extras)
        push!(parts, " [", join(x.extras, ", "), "]")
    end
    if x.version != ""
        push!(parts, " ", x.version)
    end
    return join(parts)
end

function pixispec(x::PipPkgSpec)
    spec = Dict{String,Any}()
    if startswith(x.version, "@")
        url = strip(x.version[2:end])
        if startswith(url, "git+")
            url = url[5:end]
            if (m = match(r"^(.*?)@([^/@]*)$", url); m !== nothing)
                spec["git"] = m.captures[1]
                rev = m.captures[2]
                if (m = match(r"^([^#]*)#(.*)$", rev); m !== nothing)
                    # spec["tag"] = m.captures[1]
                    spec["rev"] = m.captures[2]
                else
                    spec["rev"] = rev
                end
            else
                spec["git"] = url
            end
        else
            spec["url"] = url
        end
    else
        spec["version"] = x.version == "" ? "*" : x.version
    end
    if !isempty(x.extras)
        spec["extras"] = x.extras
    end
    if length(spec) == 1 && haskey(spec, "version")
        spec["version"]
    else
        spec
    end
end
