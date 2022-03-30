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
            pkgs, chans, pippkgs = parse_deps(TOML.parsefile(fn))
            for pkg in pkgs
                get!(Dict{String,PkgSpec}, packages, pkg.name)[fn] = pkg
            end
            if isempty(chans)
                push!(channels, ChannelSpec("conda-forge"))
            else
                append!(channels, chans)
            end
            for pkg in pippkgs
                get!(Dict{String,PipPkgSpec}, pip_packages, pkg.name)[fn] = pkg
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

function _resolve_diff(old_specs, new_specs)
    # group by package name
    old_dict = Dict{String,Set{PkgSpec}}()
    for spec in old_specs
        push!(get!(Set{PkgSpec}, old_dict, spec.name), spec)
    end
    new_dict = Dict{String,Set{PkgSpec}}()
    for spec in new_specs
        push!(get!(Set{PkgSpec}, new_dict, spec.name), spec)
    end
    # find packages which have been removed
    removed = String[k for k in keys(old_dict) if !haskey(new_dict, k)]
    # find packages which are new or have changed
    added = PkgSpec[x for (k, v) in new_dict if get(old_dict, k, nothing) != v for x in v]
    # don't remove pip, this avoids some flip-flopping when removing pip packages
    filter!(x->x!="pip", removed)
    return (removed, added)
end

function _resolve_pip_diff(old_specs, new_specs)
    # make dicts
    old_dict = Dict{String,PipPkgSpec}(spec.name => spec for spec in old_specs)
    new_dict = Dict{String,PipPkgSpec}(spec.name => spec for spec in new_specs)
    # find packages which have been removed
    removed = String[k for k in keys(old_dict) if !haskey(new_dict, k)]
    # find packages which are new or have changed
    added = PipPkgSpec[v for (k, v) in new_dict if get(old_dict, k, nothing) != v]
    return (removed, added)
end

function _verbosity()
    parse(Int, get(ENV, "JULIA_CONDAPKG_VERBOSITY", "-1"))
end

function _verbosity_flags()
    n = _verbosity()
    n < 0 ? ["-"*"q"^(-n)] : n > 0 ? ["-"*"v"^n] : String[]
end

function _resolve_conda_remove_all(io, conda_env)
    vrb = _verbosity_flags()
    cmd = conda_cmd(`remove $vrb -y -p $conda_env --all`, io=io)
    flags = append!(["-y", "--all"], vrb)
    _run(io, cmd, "Removing environment", flags=flags)
    nothing
end

function _resolve_conda_install(io, conda_env, specs, channels; create=false)
    args = String[]
    for spec in specs
        push!(args, specstr(spec))
    end
    for channel in channels
        push!(args, "-c", specstr(channel))
    end
    vrb = _verbosity_flags()
    cmd = conda_cmd(`$(create ? "create" : "install") $vrb -y -p $conda_env --override-channels --no-channel-priority $args`, io=io)
    flags = append!(["-y", "--override-channels", "--no-channel-priority"], vrb)
    _run(io, cmd, "Installing packages", flags=flags)
    nothing
end

function _resolve_conda_remove(io, conda_env, pkgs)
    vrb = _verbosity_flags()
    cmd = conda_cmd(`remove $vrb -y -p $conda_env $pkgs`, io=io)
    flags = append!(["-y"], vrb)
    _run(io, cmd, "Removing packages", flags=flags)
    nothing
end

function _resolve_pip_install(io, pip_specs, load_path)
    args = String[]
    for spec in pip_specs
        push!(args, specstr(spec))
    end
    vrb = _verbosity_flags()
    flags = vrb
    old_load_path = STATE.load_path
    try
        STATE.resolved = true
        STATE.load_path = load_path
        withenv() do
            pip = which("pip")
            cmd = `$pip install $vrb $args`
            _run(io, cmd, "Installing Pip packages", flags=flags)
        end
    finally
        STATE.resolved = false
        STATE.load_path = old_load_path
    end
    nothing
end

function _resolve_pip_remove(io, pkgs, load_path)
    vrb = _verbosity_flags()
    flags = append!(["-y"], vrb)
    old_load_path = STATE.load_path
    try
        STATE.resolved = true
        STATE.load_path = load_path
        withenv() do
            pip = which("pip")
            cmd = `$pip uninstall $vrb -y $pkgs`
            _run(io, cmd, "Removing Pip packages", flags=flags)
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
    if _verbosity() ≥ 0
        lines = _cmdlines(cmd, flags)
        for (i, line) in enumerate(lines)
            pre = i==length(lines) ? "└ " : "│ "
            print(io, "             ", pre)
            printstyled(io, line, color=:light_black)
            println(io)
        end
    end
    run(cmd)
end

function resolve(; force::Bool=false, io::IO=stderr, interactive::Bool=false, dry_run::Bool=false)
    # if frozen, do nothing
    if STATE.frozen
        return
    end
    # if backend is Null, assume resolved
    if backend() == :Null
        interactive && _log(io, "Using the Null backend, nothing to do")
        STATE.resolved = true
        return
    end
    # skip resolving if already resolved and LOAD_PATH unchanged
    # this is a very fast check which avoids touching the file system
    load_path = Base.load_path()
    if !force && STATE.resolved && STATE.load_path == load_path
        interactive && _log(io, "Dependencies already up to date")
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
        interactive && _log(io, "Dependencies already up to date")
        return
    end
    # find all dependencies
    (packages, channels, pip_packages, extra_path) = _resolve_find_dependencies(io, load_path)
    # install pip if there are pip packages to install
    if !isempty(pip_packages) && !haskey(packages, "pip")
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
    if !force && isfile(meta_file)
        meta = open(read_meta, meta_file)
        @assert meta !== nothing
        if stat(conda_env).mtime < meta.timestamp && (isdir(conda_env) || (isempty(meta.packages) && isempty(meta.pip_packages)))
            removed_pkgs, added_specs = _resolve_diff(meta.packages, specs)
            removed_pip_pkgs, added_pip_specs = _resolve_pip_diff(meta.pip_packages, pip_specs)
            changed = false
            if !isempty(removed_pip_pkgs)
                dry_run && return
                changed = true
                _resolve_pip_remove(io, removed_pip_pkgs, load_path)
            end
            if !isempty(removed_pkgs)
                dry_run && return
                changed = true
                _resolve_conda_remove(io, conda_env, removed_pkgs)
            end
            if !isempty(specs) && (!isempty(added_specs) || changed)
                dry_run && return
                changed = true
                _resolve_conda_install(io, conda_env, specs, channels)
            end
            if !isempty(pip_specs) && (!isempty(added_pip_specs) || changed)
                dry_run && return
                changed = true
                _resolve_pip_install(io, pip_specs, load_path)
            end
            if !changed
                _log(io, "Dependencies already up to date")
            end
            @goto save_meta
        end
    end
    # dry run bails out before touching the environment
    dry_run && return
    # remove environment
    mkpath(meta_dir)
    if isdir(conda_env)
        _resolve_conda_remove_all(io, conda_env)
    end
    # create conda environment
    _resolve_conda_install(io, conda_env, specs, channels; create=true)
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

function is_resolved()
    resolve(io=devnull, dry_run=true)
    STATE.resolved
end
