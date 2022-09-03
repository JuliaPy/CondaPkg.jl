# The functions in CondaPkg.PkgREPL are not API
# but calling them is the closest thing to calling
# the Pkg REPL.

@testitem "add/rm package" begin
    include("setup.jl")
    CondaPkg.PkgREPL.add(["  six ==1.16.0 "])
    @test occursin("six", status())
    @test occursin("(==1.16.0)", status())
    CondaPkg.PkgREPL.rm([" six "])
    @test !occursin("six", status())
end

@testitem "add/rm channel" begin
    include("setup.jl")
    CondaPkg.PkgREPL.channel_add([" numba "])
    @test occursin("numba", status())
    CondaPkg.PkgREPL.channel_rm([" numba "])
    @test !occursin("numba", status())
end

@testitem "add/rm pip package" begin
    include("setup.jl")
    CondaPkg.PkgREPL.pip_add([" six ==1.16.0 "])
    @test occursin("six", status())
    @test occursin("(==1.16.0)", status())
    CondaPkg.PkgREPL.pip_rm([" six "])
    @test !occursin("six", status())
end

@testitem "status" begin
    include("setup.jl")
    # TODO: capture the output and check it equals status()
    CondaPkg.PkgREPL.status()
end

@testitem "resolve" begin
    include("setup.jl")
    CondaPkg.PkgREPL.resolve()
end

@testitem "gc" begin
    include("setup.jl")
    if testgc
        CondaPkg.PkgREPL.gc()
    end
end

@testitem "run" begin
    include("setup.jl")
    # TODO: capture the output and check it contains "Python 3.10.2"
    if !isnull
        CondaPkg.PkgREPL.run(["python", "--version"])
    end
end
