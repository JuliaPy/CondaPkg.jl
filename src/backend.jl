"""All valid backends."""
const ALL_BACKENDS = (:MicroMamba, :Null, :System, :Current, :Pixi, :SystemPixi)

"""All backends that use a Conda/Mamba installer."""
const CONDA_BACKENDS = (:MicroMamba, :System, :Current)

"""All backends that use a Pixi installer."""
const PIXI_BACKENDS = (:Pixi, :SystemPixi)

function backend()
    if STATE.backend == :NotSet
        backend = getpref_backend()
        exe = getpref_exe()
        env = getpref_env()
        if backend == ""
            if exe == ""
                if env == "" && invokelatest(pixi_jll_module().is_available)::Bool
                    # cannot currently use pixi backend if env preference is set
                    # (see resolve())
                    backend = "Pixi"
                elseif invokelatest(micromamba_module().is_available)::Bool
                    backend = "MicroMamba"
                else
                    error(
                        "neither pixi nor micromamba is automatically available on your system",
                    )
                end
            else
                if occursin("pixi", lowercase(basename(exe)))
                    backend = "SystemPixi"
                else
                    backend = "System"
                end
            end
        end
        if backend == "MicroMamba"
            STATE.backend = :MicroMamba
        elseif backend == "Null"
            STATE.backend = :Null
        elseif backend == "Pixi"
            STATE.backend = :Pixi
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
        invokelatest(micromamba_module().cmd, args, io = io)::Cmd
    elseif b in CONDA_BACKENDS
        STATE.condaexe == "" && error("this is a bug")
        `$(STATE.condaexe) $args`
    else
        error("Cannot run conda when backend is $b.")
    end
end

default_pixi_cache_dir() = @get_scratch!("pixi_cache")

function pixi_cmd(args = ``; io::IO = stderr)
    b = backend()
    if b == :Pixi
        pixiexe = invokelatest(pixi_jll_module().pixi)::Cmd
        if !haskey(ENV, "PIXI_CACHE_DIR") && !haskey(ENV, "RATTLER_CACHE_DIR")
            # if the cache dirs are not set, use a scratch dir
            pixi_cache_dir = default_pixi_cache_dir()
            pixiexe = addenv(
                pixiexe,
                "PIXI_CACHE_DIR" => pixi_cache_dir,
                "RATTLER_CACHE_DIR" => pixi_cache_dir,
            )
        end
        `$pixiexe $args`
    elseif b in PIXI_BACKENDS
        STATE.pixiexe == "" && error("this is a bug")
        `$(STATE.pixiexe) $args`
    else
        error("Cannot run pixi when backend is $b.")
    end
end
