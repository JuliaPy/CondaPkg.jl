"""
Functions for interacting with the `CondaPkg.toml` file in the current project.

This is the main `Pkg`-like API, with functions like `add`, `rm`, `status`.
"""

function cur_deps_file()
    e = Base.load_path()[1]
    if !isdir(e)
        e = dirname(e)
        @assert isdir(e)
    end
    joinpath(e, "CondaPkg.toml")
end

function read_deps(; file = cur_deps_file())
    isfile(file) ? TOML.parsefile(file) : Dict{String,Any}()
end

function write_deps(toml; file = cur_deps_file())
    if isempty(toml)
        if isfile(file)
            Base.rm(file)
        end
    else
        open(file, "w") do io
            TOML.print(io, toml)
        end
    end
    return
end

function parse_deps(toml; main::Bool = true, dev::Bool = false)
    # packages
    packages = PkgSpec[]
    if main && haskey(toml, "deps")
        deps = _convert(Dict{String,Any}, toml["deps"])
        for (name, dep) in deps
            version = ""
            channel = ""
            build = ""
            if dep isa AbstractString
                version = _convert(String, dep)
            elseif dep isa AbstractDict
                for (k, v) in _convert(Dict{String,Any}, dep)
                    if k == "version"
                        version = _convert(String, v)
                    elseif k == "channel"
                        channel = _convert(String, v)
                    elseif k == "build"
                        build = _convert(String, v)
                    else
                        error("deps keys must be 'version', 'channel' or 'build', got '$k'")
                    end
                end
            else
                error("deps must be String or Dict, got $(typeof(dep))")
            end
            pkg = PkgSpec(name, version = version, channel = channel, build = build)
            push!(packages, pkg)
        end
    end

    # channels
    channels = ChannelSpec[]
    if main && haskey(toml, "channels")
        chan_names = _convert(Vector{String}, toml["channels"])
        for name in chan_names
            push!(channels, ChannelSpec(name))
        end
    end

    # pip packages
    pip_packages = PipPkgSpec[]
    if main && haskey(toml, "pip")
        pip = _convert(Dict{String,Any}, toml["pip"])
        if haskey(pip, "deps")
            pip_deps = _convert(Dict{String,Any}, pip["deps"])
            for (name, dep) in pip_deps
                version = ""
                binary = ""
                extras = String[]
                editable = false
                if dep isa AbstractString
                    version = _convert(String, dep)
                elseif dep isa AbstractDict
                    for (k, v) in _convert(Dict{String,Any}, dep)
                        if k == "version"
                            version = _convert(String, v)
                        elseif k == "binary"
                            binary = _convert(String, v)
                        elseif k == "extras"
                            extras = _convert(Vector{String}, v)
                        elseif k == "editable"
                            editable = _convert(Bool, v)
                        else
                            error(
                                "pip.deps keys must be 'version', 'extras', 'binary' or 'editable', got '$k'",
                            )
                        end
                    end
                else
                    error("pip.deps must be String or Dict, got $(typeof(dep))")
                end
                pkg = PipPkgSpec(
                    name,
                    version = version,
                    binary = binary,
                    extras = extras,
                    editable = editable,
                )
                push!(pip_packages, pkg)
            end
        end
    end

    # dev dependencies
    if dev && haskey(toml, "dev")
        devdeps = parse_deps(toml["dev"])
        append!(packages, devdeps.packages)
        append!(channels, devdeps.channels)
        append!(pip_packages, devdeps.pip_packages)
    end

    # done
    return (packages = packages, channels = channels, pip_packages = pip_packages)
end

function read_parsed_deps(file; main = true, dev = false)
    return parse_deps(read_deps(; file); main, dev)
end

function current_packages()
    b = backend()
    if b in CONDA_BACKENDS
        cmd = conda_cmd(`list -p $(envdir()) --json`)
        pkglist = JSON3.read(cmd)
    elseif b in PIXI_BACKENDS
        cmd =
            pixi_cmd(`list --manifest-path $(joinpath(STATE.meta_dir, "pixi.toml")) --json`)
        pkglist = JSON3.read(cmd)
        pkglist = [pkg for pkg in pkglist if pkg.kind == "conda"]
    end
    Dict(normalise_pkg(pkg.name) => pkg for pkg in pkglist)
end

function current_pip_packages()
    b = backend()
    if b in CONDA_BACKENDS
        pkglist = withenv() do
            cmd = `$(which("pip")) list --format=json`
            JSON3.read(cmd)
        end
    elseif b in PIXI_BACKENDS
        cmd =
            pixi_cmd(`list --manifest-path $(joinpath(STATE.meta_dir, "pixi.toml")) --json`)
        pkglist = JSON3.read(cmd)
        pkglist = [pkg for pkg in pkglist if pkg.kind == "pypi"]
    end
    Dict(normalise_pip_pkg(pkg.name) => pkg for pkg in pkglist)
end

"""
    status()

Show the status of the current environment.

This does not include dependencies from nested environments.
"""
function status(; io::IO = stderr)
    # collect information
    dfile = cur_deps_file()
    resolved = is_resolved()
    isnull = backend() == :Null
    dtoml = read_deps(; file = dfile)
    pkgs, channels, pippkgs = parse_deps(dtoml)
    dev_pkgs, dev_channels, dev_pippkgs = parse_deps(dtoml; main = false, dev = true)
    curpkgs =
        resolved && !isnull && (!isempty(pkgs) || !isempty(dev_pkgs)) ? current_packages() :
        nothing
    curpippkgs =
        resolved && !isnull && (!isempty(pippkgs) || !isempty(dev_pippkgs)) ?
        current_pip_packages() : nothing
    blank =
        isempty(pkgs) &&
        isempty(channels) &&
        isempty(pippkgs) &&
        isempty(dev_pkgs) &&
        isempty(dev_channels) &&
        isempty(dev_pippkgs)

    # print status
    printstyled(io, "CondaPkg Status", color = :light_green)
    printstyled(io, " ", dfile, bold = true)
    if blank
        print(io, " (empty)")
    end
    println(io)
    if !resolved
        printstyled(io, "Not Resolved", color = :yellow)
        println(io, " (resolve first for more information)")
    end
    if isnull
        printstyled(io, "Using the Null backend", color = :yellow)
        println(io, " (dependencies shown here are not being managed)")
    end
    if resolved
        printstyled(io, "Environment", bold = true, color = :cyan)
        println(io)
        println(io, "  ", STATE.conda_env)
    end
    function show_pkgs(pkgs, title)
        isempty(pkgs) && return
        printstyled(io, title, bold = true, color = :cyan)
        println(io)
        sort!(pkgs, by = x -> x.name)
        for pkg in pkgs
            print(io, "  ", pkg.name)
            if curpkgs !== nothing
                curpkg = get(curpkgs, pkg.name, nothing)
                if curpkg === nothing
                    printstyled(io, " uninstalled", color = :red)
                else
                    print(io, " v", curpkg.version)
                end
            end
            specparts = String[]
            pkg.version == "" || push!(specparts, pkg.version)
            pkg.channel == "" || push!(specparts, "channel=$(pkg.channel)")
            pkg.build == "" || push!(specparts, "build=$(pkg.build)")
            isempty(specparts) ||
                printstyled(io, " (", join(specparts, ", "), ")", color = :light_black)
            println(io)
        end
    end
    show_pkgs(pkgs, "Packages")
    show_pkgs(dev_pkgs, "Dev Packages")
    function show_channels(channels, title)
        isempty(channels) && return
        printstyled(io, title, bold = true, color = :cyan)
        println(io)
        sort!(channels, by = x -> x.name)
        for chan in channels
            println(io, "  ", chan.name)
        end
    end
    show_channels(channels, "Channels")
    show_channels(channels, "Dev Channels")
    function show_pippkgs(pippkgs, title)
        isempty(pippkgs) && return
        printstyled(io, title, bold = true, color = :cyan)
        println(io)
        sort!(pippkgs, by = x -> x.name)
        for pkg in pippkgs
            print(io, "  ", pkg.name)
            if curpippkgs !== nothing
                curpkg = get(curpippkgs, pkg.name, nothing)
                if curpkg === nothing
                    printstyled(io, " uninstalled", color = :red)
                else
                    print(io, " v", curpkg.version)
                end
            end
            specparts = String[]
            pkg.version == "" || push!(specparts, pkg.version)
            pkg.binary == "" || push!(specparts, "$(pkg.binary)-binary")
            if !isempty(pkg.extras)
                push!(specparts, "[$(join(pkg.extras, ", "))]")
            end
            if pkg.editable
                push!(specparts, "editable")
            end
            isempty(specparts) ||
                printstyled(io, " (", join(specparts, ", "), ")", color = :light_black)
            println(io)
        end
    end
    show_pippkgs(pippkgs, "Pip Packages")
    show_pippkgs(dev_pippkgs, "Dev Pip Packages")
end

# Do nothing for existing specs
_to_spec(s::Union{PkgSpec,PipPkgSpec,ChannelSpec}; channel = "") = s
# Convert strings to PkgSpec
_to_spec(s::AbstractString; channel = "") = PkgSpec(s; channel)

function _add_or_rm(
    op!::Function,
    pkgs::AbstractVector;
    channel = "",
    resolve = true,
    file = cur_deps_file(),
    io::IO = stderr,
    dev::Bool = false,
    kw...,
)
    old_content = (resolve && isfile(file)) ? read(file) : nothing
    toml = read_deps(; file)

    for pkg in pkgs
        spec = _to_spec(pkg; channel)
        if dev
            devtoml = get!(Dict{String,Any}, toml, "dev")
            op!(devtoml, spec)
            isempty(devtoml) && delete!(toml, "dev")
        else
            op!(toml, spec)
        end
    end
    write_deps(toml; file)
    STATE.resolved = false
    if resolve
        try
            CondaPkg.resolve(; io = io, kw...)
        catch
            _log(io, "Resolve failed, reverting $file")
            if old_content === nothing
                Base.rm(file)
            else
                write(file, old_content)
            end
            rethrow()
        end
    end
    return
end

function add(
    pkgs::AbstractVector;
    channel = "",
    resolve = true,
    file = cur_deps_file(),
    io::IO = stderr,
    kw...,
)
    _add_or_rm(add!, pkgs; channel, resolve, file, io, kw...)
end

add(pkg::Union{PkgSpec,PipPkgSpec,ChannelSpec}; kw...) = add([pkg]; kw...)

function rm(
    pkgs::AbstractVector;
    resolve = true,
    file = cur_deps_file(),
    io::IO = stderr,
    kw...,
)
    _add_or_rm(rm!, pkgs; channel = "", resolve, file, io, kw...)
end

rm(pkg::Union{PkgSpec,PipPkgSpec,ChannelSpec}; kw...) = rm([pkg]; kw...)

function add!(toml, pkg::PkgSpec)
    deps = get!(Dict{String,Any}, toml, "deps")
    filter!(kv -> normalise_pkg(kv[1]) != pkg.name, deps)
    dep = Dict{String,Any}()
    if pkg.version != ""
        dep["version"] = pkg.version
    end
    if pkg.channel != ""
        dep["channel"] = pkg.channel
    end
    if pkg.build != ""
        dep["build"] = pkg.build
    end
    if issubset(keys(dep), ["version"])
        deps[pkg.name] = pkg.version
    else
        deps[pkg.name] = dep
    end
end

function add!(toml, channel::ChannelSpec)
    channels = get!(Vector{Any}, toml, "channels")
    push!(channels, channel.name)
end

function add!(toml, pkg::PipPkgSpec)
    pip = get!(Dict{String,Any}, toml, "pip")
    deps = get!(Dict{String,Any}, pip, "deps")
    filter!(kv -> normalise_pip_pkg(kv[1]) != pkg.name, deps)
    dep = Dict{String,Any}()
    if pkg.version != ""
        dep["version"] = pkg.version
    end
    if pkg.binary != ""
        dep["binary"] = pkg.binary
    end
    if !isempty(pkg.extras)
        dep["extras"] = pkg.extras
    end
    if pkg.editable
        dep["editable"] = pkg.editable
    end
    if issubset(keys(dep), ["version"])
        deps[pkg.name] = pkg.version
    else
        deps[pkg.name] = dep
    end
end

function rm!(toml, pkg::PkgSpec)
    deps = get!(Dict{String,Any}, toml, "deps")
    n = length(deps)
    filter!(kv -> normalise_pkg(kv[1]) != pkg.name, deps)
    length(deps) < n || error("package not found: $(pkg.name)")
    isempty(deps) && delete!(toml, "deps")
end

function rm!(toml, channel::ChannelSpec)
    channels = get!(Vector{Any}, toml, "channels")
    n = length(channels)
    filter!(c -> normalise_channel(c) != channel.name, channels)
    length(channels) < n || error("channel not found: $(channel.name)")
    isempty(channels) && delete!(toml, "channels")
end

function rm!(toml, pkg::PipPkgSpec)
    pip = get!(Dict{String,Any}, toml, "pip")
    deps = get!(Dict{String,Any}, pip, "deps")
    n = length(deps)
    filter!(kv -> normalise_pip_pkg(kv[1]) != pkg.name, deps)
    length(deps) < n || error("pip package not found: $(pkg.name)")
    isempty(deps) && delete!(pip, "deps")
    isempty(pip) && delete!(toml, "pip")
end

"""
    add(pkg; version="", channel="", build="", resolve=true, dev=false)
    add([pkg1, pkg2, ...]; channel="", resolve=true, dev=false)

Adds a dependency to the current environment.
"""
add(pkg::AbstractString; version = "", channel = "", build = "", kw...) =
    add(PkgSpec(pkg, version = version, channel = channel, build = build); kw...)

"""
    rm(pkg; resolve=true, dev=false)
    rm([pkg1, pkg2, ...]; resolve=true, dev=false)

Removes a dependency from the current environment.
"""
rm(pkg::AbstractString; kw...) = rm(PkgSpec(pkg); kw...)

"""
    add_channel(channel; resolve=true, dev=false)

Adds a channel to the current environment.
"""
add_channel(channel::AbstractString; kw...) = add(ChannelSpec(channel); kw...)

"""
    rm_channel(channel; resolve=true, dev=false)

Removes a channel from the current environment.
"""
rm_channel(channel::AbstractString; kw...) = rm(ChannelSpec(channel); kw...)

"""
    add_pip(pkg; version="", binary="", extras=[], resolve=true, editable=false, dev=false)

Adds a pip dependency to the current environment.

!!! warning

    Use conda dependencies instead if at all possible. Pip does not handle version
    conflicts gracefully, so it is possible to get incompatible versions.
"""
add_pip(
    pkg::AbstractString;
    version = "",
    binary = "",
    extras = String[],
    editable = false,
    kw...,
) = add(
    PipPkgSpec(
        pkg,
        version = version,
        binary = binary,
        extras = extras,
        editable = editable,
    );
    kw...,
)

"""
    rm_pip(pkg; resolve=true, dev=false)

Removes a pip dependency from the current environment.
"""
rm_pip(pkg::AbstractString; kw...) = rm(PipPkgSpec(pkg); kw...)
