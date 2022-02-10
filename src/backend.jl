const SYSTEM_BACKENDS = Dict(
    "SystemConda" => ["conda"],
    "SystemMamba" => ["mamba"],
    "SystemMicroMamba" => ["micromamba"],
    "System" => ["micromamba", "mamba", "conda"],
    "" => ["micromamba", "mamba", "conda"],
)

function backend()
    if STATE.backend == :NotSet
        backend = get(ENV, "JULIA_CONDAPKG_BACKEND", "")
        exe = get(ENV, "JULIA_CONDAPKG_EXE", "")
        if backend == "MicroMamba" || (backend == "" && exe == "")
            STATE.backend = :MicroMamba
        elseif haskey(SYSTEM_BACKENDS, backend) || (backend == "")
            exe2, kind = find_conda(exe, SYSTEM_BACKENDS[backend])
            if kind == "conda"
                STATE.backend = :SystemConda
            elseif kind == "mamba"
                STATE.backend = :SystemMamba
            elseif kind == "micromamba"
                STATE.backend = :SystemMicroMamba
            else
                @assert false
            end
            STATE.condaexe = exe2
        else
            error("invalid backend: JULIA_CONDAPKG_BACKEND=$(repr(backend))")
        end
    end
    STATE.backend
end

function find_conda(exe, kinds)
    for kind in kinds
        exe2 = Sys.which(exe == "" ? kind : exe)
        exe2 === nothing && continue
        startswith(lowercase(basename(exe2)), kind) || continue
        return (exe2, kind)
    end
    if exe == ""
        error("could not find $(join(kinds, ", ", " or ")), please ensure it is installed and in your PATH, or set JULIA_CONDAPKG_EXE to its location")
    else
        error("not a valid $(join(kinds, ", ", " or ")) executable: JULIA_CONDAPKG_EXE=$(repr(exe))")
    end
end

function conda_cmd(args=``; io::IO=stderr)
    b = backend()
    if b == :MicroMamba
        MicroMamba.cmd(args, io=io)
    elseif b == :SystemMicroMamba || b == :SystemMamba || b == :SystemConda
        `$(STATE.condaexe) $args`
    else
        @assert false
    end
end
