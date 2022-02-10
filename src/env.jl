"""
This file defines functions for interacting with the environment, such as `withenv()` and
`which()`. They all automatically resolve first.
"""

"""
    activate!(env)

"Activate" the Conda environment by modifying the given dict of environment variables.
"""
function activate!(e)
    old_path = get(e, "PATH", "")
    d = envdir()
    path_sep = Sys.iswindows() ? ';' : ':'
    new_path = join(bindirs(), path_sep)
    exe = STATE.backend == :MicroMamba ? MicroMamba.executable() : STATE.condaexe
    new_path = "$(new_path)$(path_sep)$(dirname(exe))"
    if old_path != ""
        new_path = "$(new_path)$(path_sep)$(old_path)"
    end
    e["PATH"] = new_path
    e["CONDA_PREFIX"] = d
    e["CONDA_DEFAULT_ENV"] = d
    e["CONDA_SHLVL"] = "1"
    e["CONDA_PROMPT_MODIFIER"] = "($d) "
    if STATE.backend == :MicroMamba
        e["MAMBA_ROOT_PREFIX"] = MicroMamba.root_dir()
    end
    e
end

"""
    withenv(f::Function)

Call `f()` while the Conda environment is active.
"""
function withenv(f::Function)
    old_env = copy(ENV)
    # shell("activate")
    activate!(ENV)
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
"""
function envdir(args...)
    resolve()
    joinpath(STATE.meta_dir, "env", args...)
end

"""
    bindirs()

The directories containing binaries in the Conda environment.
"""
function bindirs()
    e = envdir()
    if Sys.iswindows()
        ("$e", "$e\\Library\\mingw-w64\\bin", "$e\\Library\\usr\\bin", "$e\\Library\\bin", "$e\\Scripts", "$e\\bin")
    else
        ("$e/bin", "$e/condabin")
    end
end

"""
    which(progname)

Find the binary called `progname` in the Conda environment.
"""
function which(progname)
    # Set the PATH to dirs in the environment, then use Sys.which().
    old_path = get(ENV, "PATH", nothing)
    ENV["PATH"] = join(bindirs(), Sys.iswindows() ? ';' : ':')
    try
        Sys.which(progname)
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
function gc(; io::IO=stderr)
    resolve()
    cmd = conda_cmd(`clean -y --all`, io=io)
    _run(io, cmd, "Removing unused caches")
    nothing
end
