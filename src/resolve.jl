"""
This file defines `resolve()`, which ensures all dependencies are installed.
"""

function _resolve_top_env(load_path)
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
    top_env == "" && error("no environment in the LOAD_PATH depends on CondaPkg")
    top_env
end

function _resolve_can_skip_1(load_path, meta_file)
    meta = open(read_meta, meta_file)
    if meta !== nothing && meta.version == VERSION && meta.load_path == load_path
        timestamp = max(meta.timestamp, stat(meta_file).mtime)
        skip = true
        for env in [meta.load_path; meta.extra_path]
            dir = isfile(env) ? dirname(env) : isdir(env) ? env : continue
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
        return skip
    else
        return false
    end
end

_convert(::Type{T}, @nospecialize(x)) where {T} = convert(T, x)::T

function _resolve_find_dependencies(io, load_path)
    packages = Dict{String,Dict{String,PkgSpec}}() # name -> depsfile -> spec
    channels = ChannelSpec[]
    pip_packages = Dict{String,Dict{String,PipPkgSpec}}() # name -> depsfile -> spec
    extra_path = String[]
    for env in [load_path; [p.source for p in values(Pkg.dependencies())]]
        dir = isfile(env) ? dirname(env) : isdir(env) ? env : continue
        fn = joinpath(dir, "CondaPkg.toml")
        if isfile(fn)
            env in load_path || push!(extra_path, env)
            _log(io, "Found dependencies: $fn")
            toml = _convert(Dict{String,Any}, TOML.parsefile(fn))
            if haskey(toml, "channels")
                chans = _convert(Vector{String}, toml["channels"])
                for name in chans
                    push!(channels, ChannelSpec(name))
                end
            else
                push!(channels, ChannelSpec("conda-forge"))
            end
            if haskey(toml, "deps")
                deps = _convert(Dict{String,String}, toml["deps"])
                for (name, version) in deps
                    pspec = PkgSpec(name, version=version)
                    get!(Dict{String,PkgSpec}, packages, pspec.name)[fn] = pspec
                end
            end
            if haskey(toml, "pip")
                pip = _convert(Dict{String,Any}, toml["pip"])
                if haskey(pip, "deps")
                    deps = _convert(Dict{String,String}, pip["deps"])
                    for (name, version) in deps
                        pspec = PipPkgSpec(name, version=version)
                        get!(Dict{String,PipPkgSpec}, pip_packages, pspec.name)[fn] = pspec
                    end
                end
            end
        end
    end
    (packages, channels, pip_packages, extra_path)
end

function _resolve_merge_packages(packages)
    specs = PkgSpec[]
    for (name, pkgs) in packages
        @assert length(pkgs) > 0
        for pkg in values(pkgs)
            @assert pkg.name == name
            push!(specs, pkg)
        end
    end
    sort!(unique!(specs), by=x->x.name)
end

function _resolve_merge_pip_packages(packages)
    specs = PipPkgSpec[]
    for (name, pkgs) in packages
        @assert length(pkgs) > 0
        versions = String[]
        urls = String[]
        for (fn, pkg) in pkgs
            @assert pkg.name == name
            if startswith(pkg.version, "@")
                url = strip(pkg.version[2:end])
                if startswith(url, ".")
                    url = abspath(dirname(fn), url)
                end
                push!(urls, url)
            elseif pkg.version != ""
                push!(versions, pkg.version)
            end
        end
        sort!(unique!(urls))
        sort!(unique!(versions))
        if isempty(urls)
            version = join(versions, ",")
        elseif isempty(versions)
            length(urls) == 1 || error("multiple direct references ('@ ...') given for pip package '$name'")
            version = "@ $(urls[1])"
        else
            error("direct references ('@ ...') and version specifiers both given for pip package '$name'")
        end
        push!(specs, PipPkgSpec(name, version=version))
    end
    sort!(specs, by=x->x.name)
end

function _resolve_can_skip_2(meta_file, specs, pip_specs, conda_env)
    meta = open(read_meta, meta_file)
    return meta !== nothing && meta.packages == specs && meta.pip_packages == pip_specs && stat(conda_env).mtime < meta.timestamp
end

function _resolve_conda_remove(io, conda_env)
    cmd = MicroMamba.cmd(`remove -y -p $conda_env --all`, io=io)
    _run(io, cmd, "Removing environment", flags=["-y", "--all"])
    nothing
end

function _resolve_conda_create(io, conda_env, specs, channels)
    args = String[]
    for spec in specs
        if spec.version == ""
            push!(args, spec.name)
        else
            push!(args, "$(spec.name) $(spec.version)")
        end
    end
    for channel in channels
        push!(args, "-c", channel.name)
    end
    cmd = MicroMamba.cmd(`create -y -p $conda_env --no-channel-priority $args`, io=io)
    _run(io, cmd, "Creating environment", flags=["-y", "--no-channel-priority"])
    nothing
end

function _resolve_pip_install(io, pip_specs, load_path)
    args = String[]
    for spec in pip_specs
        if isempty(spec.version)
            push!(args, spec.name)
        else
            push!(args, "$(spec.name) $(spec.version)")
        end
    end
    old_load_path = STATE.load_path
    try
        STATE.resolved = true
        STATE.load_path = load_path
        withenv() do
            pip = which("pip")
            cmd = `$pip install $args`
            _run(io, cmd, "Installing Pip dependencies")
        end
    finally
        STATE.resolved = false
        STATE.load_path = old_load_path
    end
    nothing
end

function _log(io::IO, args...)
    printstyled(io, "    CondaPkg ", color=:green, bold=true)
    println(io, args...)
    flush(io)
end

function _cmdlines(cmd, flags)
    lines = String[]
    isarg = false
    for x in cmd.exec
        if isarg
            lines[end] *= " $x"
            isarg = false
        else
            push!(lines, x)
            isarg = length(lines) > 1 && startswith(x, "-") && x ∉ flags
        end
    end
    lines
end

function _run(io::IO, cmd::Cmd, args...; flags=String[])
    _log(io, args...)
    lines = _cmdlines(cmd, flags)
    for (i, line) in enumerate(lines)
        pre = i==length(lines) ? "└ " : "│ "
        print(io, "             ", pre)
        printstyled(io, line, color=:light_black)
        println(io)
    end
    run(cmd)
end

function resolve(; force::Bool=false, io::IO=stderr)
    # if frozen, do nothing
    if STATE.frozen
        return
    end
    # skip resolving if already resolved and LOAD_PATH unchanged
    # this is a very fast check which avoids touching the file system
    load_path = Base.load_path()
    if !force && STATE.resolved && STATE.load_path == load_path
        return
    end
    STATE.resolved = false
    STATE.load_path = load_path
    # find the topmost env in the load_path which depends on CondaPkg
    top_env = _resolve_top_env(load_path)
    STATE.meta_dir = meta_dir = joinpath(top_env, ".CondaPkg")
    meta_file = joinpath(meta_dir, "meta")
    conda_env = joinpath(meta_dir, "env")
    # skip resolving if nothing has changed since the metadata was updated
    if !force && isdir(conda_env) && isfile(meta_file) && _resolve_can_skip_1(load_path, meta_file)
        STATE.resolved = true
        return
    end
    # find all dependencies
    (packages, channels, pip_packages, extra_path) = _resolve_find_dependencies(io, load_path)
    # if there are any pip dependencies, we'd better install pip
    if !isempty(pip_packages)
        get!(Dict{String,PkgSpec}, packages, "pip")["<internal>"] = PkgSpec("pip")
        if !any(c.name in ("conda-forge", "anaconda") for c in channels)
            push!(channels, ChannelSpec("conda-forge"))
        end
    end
    # sort channels
    # (in the future we might prioritise them)
    sort!(unique!(channels), by=c->c.name)
    # merge dependencies
    specs = _resolve_merge_packages(packages)
    # merge pip dependencies
    pip_specs = _resolve_merge_pip_packages(pip_packages)
    # skip any conda calls if the dependencies haven't changed
    if !force && isfile(meta_file) && isdir(conda_env) && _resolve_can_skip_2(meta_file, specs, pip_specs, conda_env)
        _log(io, "Dependencies already up to date")
        @goto save_meta
    end
    # remove environment
    mkpath(meta_dir)
    if isdir(conda_env)
        _resolve_conda_remove(io, conda_env)
    end
    # create conda environment
    _resolve_conda_create(io, conda_env, specs, channels)
    # install pip packages
    if !isempty(pip_specs)
        _resolve_pip_install(io, pip_specs, load_path)
    end
    # save metadata
    @label save_meta
    meta = Meta(
        timestamp = time(),
        load_path = load_path,
        extra_path = extra_path,
        version = VERSION,
        packages = specs,
        channels = channels,
        pip_packages = pip_specs,
    )
    open(io->write_meta(io, meta), meta_file, "w")
    # all done
    STATE.resolved = true
    return
end
