"""All valid backends."""
const ALL_BACKENDS = (:MicroMamba, :Null, :System, :Current, :SystemPixi)

"""All backends that use a Conda/Mamba installer."""
const CONDA_BACKENDS = (:MicroMamba, :System, :Current)

"""All backends that use a Pixi installer."""
const PIXI_BACKENDS = (:SystemPixi,)

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
        elseif backend == "SystemPixi"
            ok = false
            exe2 = Sys.which(exe == "" ? "pixi" : exe)
            if exe2 === nothing
                if exe == ""
                    error("could not find a pixi executable")
                else
                    error("not an executable: $exe")
                end
            end
            STATE.backend = :SystemPixi
            STATE.pixiexe = exe2
        else
            error("invalid backend: $backend")
        end
    end
    @assert STATE.backend in ALL_BACKENDS
    STATE.backend
end

function conda_cmd(args = ``; io::IO = stderr)
    b = backend()
    if b == :MicroMamba
        MicroMamba.cmd(args, io = io)
    elseif b in CONDA_BACKENDS
        STATE.condaexe == "" && error("this is a bug")
        `$(STATE.condaexe) $args`
    else
        error("Cannot run conda when backend is $b.")
    end
end

function pixi_cmd(args = ``; io::IO = stderr)
    b = backend()
    if b in PIXI_BACKENDS
        STATE.pixiexe == "" && error("this is a bug")
        `$(STATE.pixiexe) $args`
    else
        error("Cannot run pixi when backend is $b.")
    end
end
