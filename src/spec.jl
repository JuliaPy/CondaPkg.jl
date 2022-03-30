"""
This file defines the types `PkgSpec`, `ChannelSpec` and `PipPkgSpec`, plus related
validation and normalisation functions.
"""

is_valid_string(name; allow_regex=false, allow_glob=false) = ('\'' ∉ name) && ('"' ∉ name) && (allow_regex || !(startswith(name, "^") && endswith(name, "\$"))) && (allow_glob || '*' ∉ name)

struct PkgSpec
    name::String
    version::String
    channel::String
    function PkgSpec(name; version="", channel="")
        name = validate_pkg(name)
        version = validate_version(version)
        channel = validate_channel(channel, allow_empty=true)
        new(name, version, channel)
    end
end

Base.:(==)(x::PkgSpec, y::PkgSpec) = (x.name == y.name) && (x.version == y.version) && (x.channel == y.channel)
Base.hash(x::PkgSpec, h::UInt) = hash(x.channel, hash(x.version, hash(x.name, h)))

is_valid_pkg(name) = occursin(r"^\s*[-_.a-zA-Z0-9]+\s*$", name) && is_valid_string(name)

normalise_pkg(name) = lowercase(strip(name))

validate_pkg(name) =
    if is_valid_pkg(name)
        normalise_pkg(name)
    else
        error("invalid package: $(repr(name))")
    end

is_valid_version(ver) = occursin(r"^\s*($|[!<>=0-9])", ver) && is_valid_string(ver)

normalise_version(ver) = strip(ver)

validate_version(ver) =
    if is_valid_version(ver)
        normalise_version(ver)
    else
        error("invalid version: $(repr(ver))")
    end

function specstr(x::PkgSpec)
    parts = String[]
    x.version == "" || push!(parts, "version='$(x.version)'")
    x.channel == "" || push!(parts, "channel='$(x.channel)'")
    suffix = isempty(parts) ? "" : string("[", join(parts, ", "), "]")
    string(x.name, suffix)
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

is_valid_channel(name; allow_empty=false) = (allow_empty || !isempty(strip(name))) && is_valid_string(name)

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
    function PipPkgSpec(name; version="")
        name = validate_pip_pkg(name)
        version = validate_pip_version(version)
        new(name, version)
    end
end

Base.:(==)(x::PipPkgSpec, y::PipPkgSpec) = (x.name == y.name) && (x.version == y.version)
Base.hash(x::PipPkgSpec, h::UInt) = hash(x.version, hash(x.name, h))

is_valid_pip_pkg(name) = occursin(r"^\s*[-_.A-Za-z0-9]+\s*$", name)

normalise_pip_pkg(name) = replace(lowercase(strip(name)), r"[-._]+"=>"-")

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

specstr(x::PipPkgSpec) = x.version == "" ? x.name : string(x.name, " ", x.version)
