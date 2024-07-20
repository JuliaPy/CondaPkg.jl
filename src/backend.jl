function backend()
    if STATE.backend == :NotSet
        backend = getpref(String, "backend", "JULIA_CONDAPKG_BACKEND", "")
        exe = getpref(String, "exe", "JULIA_CONDAPKG_EXE", "")
        if backend == ""
            backend = exe == "" ? "MicroMamba" : "System"
        end
        if backend == "MicroMamba"
            STATE.backend = :MicroMamba
        elseif backend == "Null"
            STATE.backend = :Null
        elseif backend == "System" || backend == "Current"
            ok = false
            for exe in (exe == "" ? ["micromamba", "mamba", "conda"] : [exe])
                exe2 = Sys.which(exe)
                if exe2 !== nothing
                    STATE.backend = Symbol(backend)
                    STATE.condaexe = exe2
                    ok = true
                    break
                end
            end
            if !ok
                if exe == ""
                    error("could not find a conda, mamba or micromamba executable")
                else
                    error("not an executable: $exe")
                end
            end
        else
            error("invalid backend: $backend")
        end
    end
    STATE.backend
end

function conda_cmd(args = ``; io::IO = stderr)
    b = backend()
    if b == :MicroMamba
        MicroMamba.cmd(args, io = io)
    elseif b in (:System, :Current)
        `$(STATE.condaexe) $args`
    elseif b == :Null
        error(
            "Can not run conda command when backend is Null. Manage conda actions outside of julia.",
        )
    else
        @assert false
    end
end
