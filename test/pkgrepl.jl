# The functions in CondaPkg.PkgREPL are not API
# but calling them is the closest thing to calling
# the Pkg REPL.

@testitem "add/rm package" begin
    include("setup.jl")
    CondaPkg.PkgREPL.add(["six==1.16.0"])
    @test occursin("six", status())
    @test occursin("(==1.16.0)", status())
    CondaPkg.PkgREPL.rm(["six"])
    @test !occursin("six", status())
end

@testitem "add/rm channel" begin
    include("setup.jl")
    CondaPkg.PkgREPL.channel_add(["numba"])
    @test occursin("numba", status())
    CondaPkg.PkgREPL.channel_rm(["numba"])
    @test !occursin("numba", status())
end

@testitem "add/rm pip package" begin
    include("setup.jl")
    CondaPkg.PkgREPL.pip_add(["six==1.16.0", "pydantic[email]==2.9.2"])
    @test occursin("six", status())
    @test occursin("(==1.16.0)", status())
    @test occursin("pydantic", status())
    @test occursin("(==2.9.2, [email])", status())
    CondaPkg.PkgREPL.pip_rm(["six", "pydantic"])
    @test !occursin("six", status())
    @test !occursin("pydantic", status())
end

@testitem "status" begin
    include("setup.jl")
    # TODO: capture the output and check it equals status()
    CondaPkg.PkgREPL.status()
end

@testitem "resolve" begin
    include("setup.jl")
    CondaPkg.PkgREPL.resolve()
    @test CondaPkg.is_resolved()
end

@testitem "update" begin
    include("setup.jl")
    CondaPkg.PkgREPL.update()
    @test CondaPkg.is_resolved()
end

@testitem "gc" begin
    include("setup.jl")
    testgc && CondaPkg.PkgREPL.gc()
    @test true
end

@testitem "run" begin
    include("setup.jl")
    if !isnull
        CondaPkg.add("python", version = "==3.10.2")
        fn = tempname()
        # run python --version and check the output
        open(fn, "w") do io
            redirect_stdout(io) do
                CondaPkg.PkgREPL.run(["python", "--version"])
            end
        end
        @test contains(read(fn, String), "3.10.2")
        # run conda --help and check the output
        # tests that conda and mamba both run whatever CondaPkg runs
        open(fn, "w") do io
            redirect_stdout(io) do
                CondaPkg.PkgREPL.run([ispixi ? "pixi" : "conda", "--help"])
            end
        end
        @test contains(read(fn, String), "--help")
        @test contains(read(fn, String), "--version")
    end
end
