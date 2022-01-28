"""
This file defines the types `PkgSpec`, `ChannelSpec` and `PipPkgSpec`, plus related
validation and normalisation functions.
"""

struct PkgSpec
    name::String
    version::String
    function PkgSpec(name; version="")
        name = validate_pkg(name)
        version = validate_version(version)
        new(name, version)
    end
end

Base.:(==)(x::PkgSpec, y::PkgSpec) = (x.name == y.name) && (x.version == y.version)
Base.hash(x::PkgSpec, h::UInt) = hash(x.version, hash(x.name, h))

is_valid_pkg(name) = occursin(r"^\s*[-_.a-zA-Z0-9]+\s*$", name)

normalise_pkg(name) = lowercase(strip(name))

validate_pkg(name) =
    if is_valid_pkg(name)
        normalise_pkg(name)
    else
        error("invalid package: $(repr(name))")
    end

is_valid_version(ver) = occursin(r"^\s*($|[!<>=0-9])", ver)

normalise_version(ver) = strip(ver)

validate_version(ver) =
    if is_valid_version(ver)
        normalise_version(ver)
    else
        error("invalid version: $(repr(ver))")
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

is_valid_channel(name) = strip(name) != ""

normalise_channel(name) = strip(name)

validate_channel(name) =
    if is_valid_channel(name)
        normalise_channel(name)
    else
        error("invalid channel: $(repr(name))")
    end

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

normalise_pip_version(ver) = lowercase(strip(ver))

validate_pip_version(ver) =
    if is_valid_pip_version(ver)
        normalise_pip_version(ver)
    else
        error("invalid pip version: $(repr(ver))")
    end
