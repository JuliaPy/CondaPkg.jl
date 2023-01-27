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
    top_env == "" && error("no environment in the LOAD_PATH ($load_path) depends on CondaPkg")
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

# For each (V, B) in this list, if Julia has libstdc++ loaded at version at least V, then
# B is a compatible bound for libstdcxx_ng.
# See https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html.
# See https://gcc.gnu.org/develop.html#timeline.
const _compatible_libstdcxx_ng_versions = [
    (v"3.4.31", ">=3.4,<=13.1"),
    (v"3.4.30", ">=3.4,<13.0"),
    (v"3.4.29", ">=3.4,<12.0"),
    (v"3.4.28", ">=3.4,<11.0"),
    (v"3.4.27", ">=3.4,<9.3"),
    (v"3.4.26", ">=3.4,<9.2"),
    (v"3.4.25", ">=3.4,<9.0"),
    (v"3.4.24", ">=3.4,<8.0"),
    (v"3.4.23", ">=3.4,<7.2"),
    (v"3.4.22", ">=3.4,<7.0"),
    (v"3.4.21", ">=3.4,<6.0"),
    (v"3.4.20", ">=3.4,<5.0"),
    (v"3.4.19", ">=3.4,<4.9"),
]

"""
    _compatible_libstdcxx_ng_version()

Version of libstdcxx-ng compatible with the libstdc++ loaded into Julia.

Specifying the package "libstdcxx-ng" with version "<=julia" will replace the version with
this one. This should be used by anything which embeds Python into the Julia process - for
instance it is used by PythonCall.
"""
function _compatible_libstdcxx_ng_version()
    if !Sys.islinux()
        return
    end
    # bound = get(ENV, "JULIA_CONDAPKG_LIBSTDCXX_VERSION_BOUND", "")
    # if bound != ""
    #     return bound
    # end
    loaded_libstdcxx_version = Base.BinaryPlatforms.detect_libstdcxx_version()
    if loaded_libstdcxx_version === nothing
        return
    end
    for (version, bound) in _compatible_libstdcxx_ng_versions
        if loaded_libstdcxx_version ≥ version
            return bound
        end
    end
end

function _resolve_find_dependencies(io, load_path)
    packages = Dict{String,Dict{String,PkgSpec}}() # name -> depsfile -> spec
    channels = ChannelSpec[]
    pip_packages = Dict{String,Dict{String,PipPkgSpec}}() # name -> depsfile -> spec
    extra_path = String[]
    orig_project = Pkg.project().path
    try
        for proj in load_path
            Pkg.activate(proj; io=devnull)
            for env in [proj; [p.source for p in values(Pkg.dependencies())]]
                dir = isfile(env) ? dirname(env) : isdir(env) ? env : continue
                fn = joinpath(dir, "CondaPkg.toml")
                if isfile(fn)
                    env in load_path || push!(extra_path, env)
                    _log(io, "Found dependencies: $fn")
                    pkgs, chans, pippkgs = read_parsed_deps(fn)
                    for pkg in pkgs
                        if pkg.name == "libstdcxx-ng" && pkg.version == "<=julia"
                            version = _compatible_libstdcxx_ng_version()
                            version === nothing && continue
                            pkg = PkgSpec(pkg; version)
                        end
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
        end
    finally
        Pkg.activate(orig_project; io=devnull)
    end
    if isempty(channels)
        push!(channels, ChannelSpec("conda-forge"))
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

function abspathurl(args...)
    path = abspath(args...)
    if Sys.iswindows()
        path = replace(path, '\\' => '/')
        @assert !startswith(path, "/") # TODO: handle \\machine\... paths
        path = "/$path"
    else
        @assert startswith(path, "/")
    end
    return "file://$path"
end

function _resolve_merge_pip_packages(packages)
    specs = PipPkgSpec[]
    for (name, pkgs) in packages
        @assert length(pkgs) > 0
        versions = String[]
        urls = String[]
        binary = ""
        for (fn, pkg) in pkgs
            @assert pkg.name == name
            if startswith(pkg.version, "@")
                url = strip(pkg.version[2:end])
                if startswith(url, ".")
                    url = abspathurl(dirname(fn), url)
                end
                push!(urls, url)
            elseif pkg.version != ""
                push!(versions, pkg.version)
            end
            if pkg.binary != ""
                if binary in ("", pkg.binary)
                    binary = pkg.binary
                else
                    error("$(binary)-binary and $(pkg.binary)-binary both specified for pip package '$name'")
                end
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
        push!(specs, PipPkgSpec(name, version=version, binary=binary))
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
    # find changes
    removed = collect(String, setdiff(keys(old_dict), keys(new_dict)))
    added = collect(String, setdiff(keys(new_dict), keys(old_dict)))
    changed = String[k for k in intersect(keys(old_dict), keys(new_dict)) if old_dict[k] != new_dict[k]]
    # don't remove pip, this avoids some flip-flopping when removing pip packages
    filter!(x->x!="pip", removed)
    return (removed, changed, added)
end

function _resolve_pip_diff(old_specs, new_specs)
    # make dicts
    old_dict = Dict{String,PipPkgSpec}(spec.name => spec for spec in old_specs)
    new_dict = Dict{String,PipPkgSpec}(spec.name => spec for spec in new_specs)
    # find changes
    removed = collect(String, setdiff(keys(old_dict), keys(new_dict)))
    added = collect(String, setdiff(keys(new_dict), keys(old_dict)))
    changed = String[k for k in intersect(keys(old_dict), keys(new_dict)) if old_dict[k] != new_dict[k]]
    return (removed, changed, added)
end

function _verbosity()
    parse(Int, get(ENV, "JULIA_CONDAPKG_VERBOSITY", "0"))
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
    (length(specs) == 0 && !create) && return  # installing 0 packages is invalid
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
    _run(io, cmd, create ? "Creating environment" : "Installing packages", flags=flags)
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
        if spec.binary == "only"
            push!(args, "--only-binary", spec.name)
        elseif spec.binary == "no"
            push!(args, "--no-binary", spec.name)
        end
    end
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

function _log(printfunc::Function, io::IO, args...; label="CondaPkg", opts...)
    printstyled(io, lpad(label, 12), " ", color=:green, bold=true)
    printfunc(io, args...; opts...)
    println(io)
    flush(io)
end

function _log(io::IO, args...; opts...)
    _log(printstyled, io, args...; opts...)
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
            _log(io, label="") do io
                print(io, pre)
                printstyled(io, line, color=:light_black)
            end
        end
    end
    run(cmd)
end

function offline()
    x = get(ENV, "JULIA_CONDAPKG_OFFLINE", "no")
    if x == "yes"
        return true
    elseif x == "no" || x == ""
        return false
    else
        error("invalid setting: JULIA_CONDAPKG_OFFLINE=$x: expecting yes or no")
    end
end

function is_clean(conda_env, meta)
    meta === nothing && return false
    conda_env == meta.conda_env || return false
    stat(conda_env).mtime ≤ meta.timestamp || return false
    isdir(conda_env) && return true
    (isempty(meta.packages) && isempty(meta.pip_packages)) && return true
    false
end

function resolve(; force::Bool=false, io::IO=stderr, interactive::Bool=false, dry_run::Bool=false)
    # if frozen, do nothing
    STATE.frozen && return
    # if backend is Null, assume resolved
    back = backend()
    if back === :Null
        interactive && _log(io, "Using the Null backend, nothing to do")
        STATE.resolved = true
        return
    end
    # skip resolving if already resolved and LOAD_PATH unchanged
    # this is a very fast check which avoids touching the file system
    load_path = Base.load_path()
    if !force && STATE.resolved && STATE.load_path == load_path
        interactive && _log(io, "Dependencies already up to date (resolved)")
        return
    end
    STATE.resolved = false
    STATE.load_path = load_path
    # find the topmost env in the load_path which depends on CondaPkg
    top_env = _resolve_top_env(load_path)
    STATE.meta_dir = meta_dir = joinpath(top_env, ".CondaPkg")
    conda_env = get(ENV, "JULIA_CONDAPKG_ENV", "")
    if back === :Current
        conda_env = get(ENV, "CONDA_PREFIX", "")
        conda_env != "" || error("CondaPkg is using the Current backend, but you are not in a Conda environment")
        shared = true
    elseif conda_env == ""
        conda_env = joinpath(meta_dir, "env")
        shared = false
    elseif startswith(conda_env, "@")
        conda_env_name = conda_env[2:end]
        conda_env_name == "" && error("JULIA_CONDAPKG_ENV shared name cannot be empty")
        any(c -> c in ('\\', '/', '@', '#'), conda_env_name) && error("JULIA_CONDAPKG_ENV shared name cannot include special characters")
        conda_env = joinpath(Base.DEPOT_PATH[1], "conda_environments", conda_env_name)
        shared = true
    else
        isabspath(conda_env) || error("JULIA_CONDAPKG_ENV must be an absolute path")
        occursin(".CondaPkg", conda_env) && error("JULIA_CONDAPKG_ENV must not be an existing .CondaPkg, select another directory")
        shared = true
    end
    STATE.conda_env = conda_env
    STATE.shared = shared
    meta_file = joinpath(meta_dir, "meta")
    lock_file = joinpath(meta_dir, "lock")
    # grap a file lock so only one process can resolve this environment at a time
    mkpath(meta_dir)
    lock = try
        Pidfile.mkpidlock(lock_file; wait=false)
    catch
        interactive && _log(io, "Waiting for lock to be freed at $lock_file")
        interactive && _log(io, "(You may delete this file if you are sure no other process is resolving)")
        Pidfile.mkpidlock(lock_file; wait=true)
    end
    try
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
            get!(Dict{String,PkgSpec}, packages, "pip")["<internal>"] = PkgSpec("pip", version=">=22.0.0")
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
        # find what has changed
        meta = isfile(meta_file) ? open(read_meta, meta_file) : nothing
        if meta === nothing
            removed_pkgs = String[]
            changed_pkgs = String[]
            added_pkgs = unique!(String[x.name for x in specs])
            removed_pip_pkgs = String[]
            changed_pip_pkgs = String[]
            added_pip_pkgs = unique!(String[x.name for x in pip_specs])
        else
            removed_pkgs, changed_pkgs, added_pkgs = _resolve_diff(meta.packages, specs)
            removed_pip_pkgs, changed_pip_pkgs, added_pip_pkgs = _resolve_pip_diff(meta.pip_packages, pip_specs)
        end
        changes = sort([
            (i>3 ? "$pkg (pip)" : pkg, mod1(i, 3))
            for (i, pkgs) in enumerate([added_pkgs, changed_pkgs, removed_pkgs, added_pip_pkgs, changed_pip_pkgs, removed_pip_pkgs])
            for pkg in pkgs
        ])
        dry_run |= offline()
        if !isempty(changes)
            _log(io, dry_run ? "Offline mode, these changes are not resolved" : "Resolving changes")
            for (pkg, i) in changes
                char = i==1 ? "+" : i==2 ? "~" : "-"
                color = i==1 ? :green : i==2 ? :yellow : :red
                _log(io, char, " ", pkg, label="", color=color)
            end
        end
        # install/uninstall packages
        if !force && is_clean(conda_env, meta)
            # the state is sufficiently clean that we can modify the existing conda environment
            changed = false
            if !isempty(removed_pip_pkgs) && !shared
                dry_run && return
                changed = true
                _resolve_pip_remove(io, removed_pip_pkgs, load_path)
            end
            if !isempty(removed_pkgs) && !shared
                dry_run && return
                changed = true
                _resolve_conda_remove(io, conda_env, removed_pkgs)
            end
            if !isempty(specs) && (!isempty(added_pkgs) || !isempty(changed_pkgs) || (meta.channels != channels) || changed || shared)
                dry_run && return
                changed = true
                _resolve_conda_install(io, conda_env, specs, channels)
            end
            if !isempty(pip_specs) && (!isempty(added_pip_pkgs) || !isempty(changed_pip_pkgs) || changed || shared)
                dry_run && return
                changed = true
                _resolve_pip_install(io, pip_specs, load_path)
            end
            changed || _log(io, "Dependencies already up to date")
        else
            # the state is too dirty, recreate the conda environment from scratch
            dry_run && return
            # remove environment
            mkpath(meta_dir)
            create = true
            if isdir(conda_env)
                if shared
                    create = false
                else
                    _resolve_conda_remove_all(io, conda_env)
                end
            end
            # create conda environment
            _resolve_conda_install(io, conda_env, specs, channels; create=create)
            # install pip packages
            isempty(pip_specs) || _resolve_pip_install(io, pip_specs, load_path)
        end
        # save metadata
        meta = Meta(
            timestamp = time(),
            conda_env = conda_env,
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
    finally
        close(lock)
    end
end

function is_resolved()
    resolve(io=devnull, dry_run=true)
    STATE.resolved
end

function update()
    resolve(force=true, interactive=true)
end
