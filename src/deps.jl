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

function read_deps(; file=cur_deps_file())
    isfile(file) ? TOML.parsefile(file) : Dict{String,Any}()
end

function write_deps(toml; file=cur_deps_file())
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

function parse_deps(toml)
    # packages
    packages = PkgSpec[]
    if haskey(toml, "deps")
        deps = _convert(Dict{String,String}, toml["deps"])
        for (name, version) in deps
            pkg = PkgSpec(name, version=version)
            push!(packages, pkg)
        end
    end

    # channels
    channels = ChannelSpec[]
    if haskey(toml, "channels")
        chan_names = _convert(Vector{String}, toml["channels"])
        for name in chan_names
            push!(channels, ChannelSpec(name))
        end
    end

    # pip packages
    pip_packages = PipPkgSpec[]
    if haskey(toml, "pip")
        pip = _convert(Dict{String,Any}, toml["pip"])
        if haskey(pip, "deps")
            pip_deps = _convert(Dict{String,String}, pip["deps"])
            for (name, version) in pip_deps
                pkg = PipPkgSpec(name, version=version)
                push!(pip_packages, pkg)
            end
        end
    end

    # done
    return (packages=packages, channels=channels, pip_packages=pip_packages)
end

function current_packages()
    cmd = MicroMamba.cmd(`-p $(envdir()) list --json`)
    pkglist = JSON3.read(cmd)
    Dict(normalise_pkg(pkg.name) => pkg for pkg in pkglist)
end

function current_pip_packages()
    pkglist = withenv() do
        cmd = `$(which("pip")) list --format=json`
        JSON3.read(cmd)
    end
    Dict(normalise_pip_pkg(pkg.name) => pkg for pkg in pkglist)
end

"""
    status()

Show the status of the current environment.

This does not include dependencies from nested environments.
"""
function status(; io::IO=stderr)
    # collect information
    dfile = cur_deps_file()
    resolved = is_resolved()
    pkgs, channels, pippkgs = parse_deps(read_deps(file=dfile))
    curpkgs = resolved && !isempty(pkgs) ? current_packages() : nothing
    curpippkgs = resolved && !isempty(pippkgs) ? current_pip_packages() : nothing
    blank = isempty(pkgs) && isempty(channels) && isempty(pippkgs)

    # print status
    printstyled(io, "CondaPkg Status", color=:light_green)
    printstyled(io, " ", dfile, bold=true)
    if blank
        print(io, " (empty)")
    end
    println(io)
    if !resolved
        printstyled(io, "Not Resolved", color=:yellow)
        println(io, " (resolve first for more information)")
    end
    if !isempty(pkgs)
        printstyled(io, "Packages", bold=true, color=:cyan)
        println(io)
        for pkg in pkgs
            print(io, "  ", pkg.name)
            if resolved
                @assert curpkgs !== nothing
                curpkg = get(curpkgs, pkg.name, nothing)
                if curpkg === nothing
                    printstyled(io, " uninstalled", color=:red)
                else
                    print(io, " v", curpkg.version)
                end
            end
            if !isempty(pkg.version)
                printstyled(io, " (", pkg.version, ")", color=:light_black)
            end
            println(io)
        end
    end
    if !isempty(channels)
        printstyled(io, "Channels", bold=true, color=:cyan)
        println(io)
        for chan in channels
            println(io, "  ", chan.name)
        end
    end
    if !isempty(pippkgs)
        printstyled(io, "Pip packages", bold=true, color=:cyan)
        println(io)
        for pkg in pippkgs
            print(io, "  ", pkg.name)
            if resolved
                @assert curpippkgs !== nothing
                curpkg = get(curpippkgs, pkg.name, nothing)
                if curpkg === nothing
                    printstyled(io, " uninstalled", color=:red)
                else
                    print(io, " v", curpkg.version)
                end
            end
            if !isempty(pkg.version)
                printstyled(io, " (", pkg.version, ")", color=:light_black)
            end
            println(io)
        end
    end
end

function add(pkgs::AbstractVector)
    toml = read_deps()
    for pkg in pkgs
        add!(toml, pkg)
    end
    write_deps(toml)
    STATE.resolved = false
    return
end

add(pkg::Union{PkgSpec,PipPkgSpec,ChannelSpec}) = add([pkg])

function add!(toml, pkg::PkgSpec)
    deps = get!(Dict{String,Any}, toml, "deps")
    filter!(kv -> normalise_pkg(kv[1]) != pkg.name, deps)
    deps[pkg.name] = pkg.version
end

function add!(toml, channel::ChannelSpec)
    channels = get!(Vector{Any}, toml, "channels")
    push!(channels, channel.name)
end

function add!(toml, pkg::PipPkgSpec)
    pip = get!(Dict{String,Any}, toml, "pip")
    deps = get!(Dict{String,Any}, pip, "deps")
    filter!(kv -> normalise_pip_pkg(kv[1]) != pkg.name, deps)
    deps[pkg.name] = pkg.version
end

function rm(pkgs::AbstractVector)
    toml = read_deps()
    for pkg in pkgs
        rm!(toml, pkg)
    end
    write_deps(toml)
    STATE.resolved = false
    return
end

rm(pkg::Union{PkgSpec,PipPkgSpec,ChannelSpec}) = rm([pkg])

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
    add(pkg; version="")

Adds a dependency to the current environment.
"""
add(pkg::AbstractString; version="") = add(PkgSpec(pkg, version=version))

"""
    rm(pkg)

Removes a dependency from the current environment.
"""
rm(pkg::AbstractString) = rm(PkgSpec(pkg))

"""
    add_channel(channel)

Adds a channel to the current environment.
"""
add_channel(channel::AbstractString) = add(ChannelSpec(channel))

"""
    rm_channel(channel)

Removes a channel from the current environment.
"""
rm_channel(channel::AbstractString) = rm(ChannelSpec(channel))

"""
    add_pip(pkg; version="")

Adds a pip dependency to the current environment.

!!! warning

    Use conda dependencies instead if at all possible. Pip does not handle version
    conflicts gracefully, so it is possible to get incompatible versions.
"""
add_pip(pkg::AbstractString; version="") = add(PipPkgSpec(pkg, version=version))

"""
    rm_pip(pkg)

Removes a pip dependency from the current environment.
"""
rm_pip(pkg::AbstractString) = rm(PipPkgSpec(pkg))
