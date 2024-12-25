"""
This file defines functions for interacting with the environment, such as `withenv()` and
`which()`. They all automatically resolve first.
"""

"""
    activate!(env; method=:simple)

"Activate" the Conda environment by modifying the given dict of environment variables. When `method` is `:simple`, the environment variables corresponding to meaning any activation hooks provided by conda packages will not be run.

An experimental `method` of `:execute` is available. In this case, the Conda environment will be activated in a bash subshell, meaning all the activation hooks will be run. All environment variables updated or created in this subshell are then changed in the current process. This method requires `bash` to be available, and has only been tested on Linux.
"""
function activate!(e; method=:simple)
    backend() in (:Null, :Current) && return e
    if method == :simple
        old_path = get(e, "PATH", "")
        d = envdir()
        path_sep = Sys.iswindows() ? ';' : ':'
        new_path = join(bindirs(), path_sep)
        if backend() == :MicroMamba
            e["MAMBA_ROOT_PREFIX"] = MicroMamba.root_dir()
            new_path = "$(new_path)$(path_sep)$(dirname(MicroMamba.executable()))"
        end
        if old_path != ""
            new_path = "$(new_path)$(path_sep)$(old_path)"
        end
        e["PATH"] = new_path
        e["CONDA_PREFIX"] = d
        e["CONDA_DEFAULT_ENV"] = d
        e["CONDA_SHLVL"] = "1"
        e["CONDA_PROMPT_MODIFIER"] = "($d) "
        e
    elseif method == :execute
        d = envdir()
        hook = join(conda_cmd(`shell hook -s bash -r $d`).exec, " ")
        activate = join(conda_cmd(`shell activate -s bash -p $d`).exec, " ")
        steps = [
            "env",
            "echo __65ab376884d7456ca97187d18a182250__",
            "eval \"\$($hook)\"",
            "eval \"\$($activate)\"",
            "env"
        ]
        steps = join(steps, " && ")
        cmd = `bash --norc --noprofile -c $steps`
        out = read(cmd, String)
        before_env = []
        after_env = []
        is_before = true
        for line in split(out, '\n')
            if line == "__65ab376884d7456ca97187d18a182250__"
                is_before = false
            end
            if occursin("=", line)
                bits = split(line, '=', limit=2)
                if is_before
                    push!(before_env, bits)
                else
                    push!(after_env, bits)
                end
            end
        end
        for (k, v) in after_env
            if haskey(e, k)
                if e[k] != v
                    e[k] = v
                end
            else
                e[k] = v
            end
        end
    end
end

"""
    withenv(f::Function, method=:simple)

Call `f()` while the Conda environment is active. See `activate!()` for details of the `method` argument.
"""
function withenv(f::Function; method=:simple)
    old_env = copy(ENV)
    # shell("activate")
    activate!(ENV; method=method)
    frozen = STATE.frozen
    STATE.frozen = true
    try
        return f()
    finally
        STATE.frozen = frozen
        # copy!(ENV, old_env) does not work (empty!(ENV) not implemented)
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

"""
    envdir(...)

The root directory of the Conda environment.

Any additional arguments are joined to the path.

Throws an error if backend is Null.
"""
function envdir(args...)
    backend() == :Null && throw(ErrorException("Can not get envdir when backend is Null."))
    resolve()
    normpath(STATE.conda_env, args...)
end

"""
    bindirs()

The directories containing binaries in the Conda environment.
"""
function bindirs()
    e = envdir()
    if Sys.iswindows()
        (
            "$e",
            "$e\\Library\\mingw-w64\\bin",
            "$e\\Library\\usr\\bin",
            "$e\\Library\\bin",
            "$e\\Scripts",
            "$e\\bin",
        )
    else
        ("$e/bin", "$e/condabin")
    end
end

"""
    which(progname)

Find the binary called `progname` in the Conda environment.
"""
function which(progname)
    backend() in (:Null, :Current) && return Sys.which(progname)
    # Set the PATH to dirs in the environment, then use Sys.which().
    old_path = get(ENV, "PATH", nothing)
    ENV["PATH"] = join(bindirs(), Sys.iswindows() ? ';' : ':')
    try
        return Sys.which(progname)
    finally
        if old_path === nothing
            delete!(ENV, "PATH")
        else
            ENV["PATH"] = old_path
        end
    end
end

"""
    gc()

Remove unused packages and caches.
"""
function gc(; io::IO = stderr)
    backend() == :Null && return
    resolve()
    cmd = conda_cmd(`clean -y --all`, io = io)
    _run(io, cmd, "Removing unused caches")
    return
end
