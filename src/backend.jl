function backend()
    if STATE.backend == :NotSet
        backend = get(ENV, "JULIA_CONDAPKG_BACKEND", "")
        exe = get(ENV, "JULIA_CONDAPKG_EXE", "")
        if backend == ""
            backend = exe == "" ? "System" : "MicroMamba"
        end
        if backend == "MicroMamba"
            STATE.backend = :MicroMamba
        elseif backend == "System"
            ok = false
            for exe in (exe == "" ? ["micromamba", "mamba", "conda"] : [exe])
                exe2 = Sys.which(exe)
                if exe2 !== nothing
                    STATE.backend = :System
                    STATE.condaexe = exe2
                    ok = true
                    break
                end
            end
            if !ok
                if exe == ""
                    error("could not find a conda, mamba or micromamba executable")
                else
                    error("not an executable: JULIA_CONDAPKG_EXE=$exe")
                end
            end
        else
            error("invalid backend: JULIA_CONDAPKG_BACKEND=$backend")
        end
    end
    STATE.backend
end

function conda_cmd(args=``; io::IO=stderr)
    b = backend()
    if b == :MicroMamba
        MicroMamba.cmd(args, io=io)
    elseif b == :System
        `$(STATE.condaexe) $args`
    else
        @assert false
    end
end
