using CondaPkg
using Test

# Only run the gc tests on CI (because it's annoying to do it locally)
testgc = get(ENV, "CI", "") == "true"

status() = sprint(io -> CondaPkg.status(io=io))

@testset "CondaPkg" begin

    @testset "add/remove channel" begin
        @test !occursin("conda-forge", status())
        CondaPkg.add_channel("conda-forge")
        @test occursin("conda-forge", status())
        CondaPkg.rm_channel("conda-forge")
        @test !occursin("conda-forge", status())
    end

    @testset "install python" begin
        @test !occursin("python", status())
        CondaPkg.add("python", version="==3.10.2")
        CondaPkg.resolve()
        CondaPkg.withenv() do
            pythonpath = joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
            @test isfile(pythonpath)
        end
        @test occursin("python", status())
    end

    @testset "install/remove python package" begin
        # verify package isn't already installed
        @test !occursin("six", status())
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add("six", version="==1.16.0")
        @test occursin("six", status())
        @test occursin("(==1.16.0)", status())
        CondaPkg.withenv() do
            run(`python -c "import six"`)
        end
        @test occursin("v1.16.0", status())

        # remove package
        CondaPkg.rm("six")
        @test !occursin("six", status())
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end
    end

    @testset "pip install/remove python package" begin
        # verify package isn't already installed
        @test !occursin("six", status())
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add_pip("six", version="==1.16.0")
        @test occursin("six", status())
        @test occursin("(==1.16.0)", status())
        CondaPkg.withenv() do
            run(`python -c "import six"`)
        end
        @test occursin("v1.16.0", status())

        # remove package
        CondaPkg.rm_pip("six")
        @test !occursin("six", status())
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end
    end


    @testset "install/remove executable package" begin
        # install package, verify that executable exists
        CondaPkg.add("curl")
        curl_path = CondaPkg.which("curl")
        @test isfile(curl_path)

        # test uninstall
        CondaPkg.rm("curl")
        CondaPkg.resolve(force=true)
        @test !isfile(curl_path)
    end

    if testgc
        @testset "gc()" begin
            # verify that micromamba clean runs without errors
            CondaPkg.gc()
        end
    end

    @testset "validation" begin
        @test_throws Exception CondaPkg.add("!invalid!package!")
        @test_throws Exception CondaPkg.add_pip("!invalid!package!")
        @test_throws Exception CondaPkg.add("valid-package", version="*invalid*version*")
        @test_throws Exception CondaPkg.add_pip("valid-package", version="*invalid*version*")
        @test_throws Exception CondaPkg.add_channel("")
        @test !occursin("valid", status())
    end

    @testset "PkgREPL" begin
        # The functions in CondaPkg.PkgREPL are not API
        # but calling them is the closest thing to calling
        # the Pkg REPL.

        # add
        CondaPkg.PkgREPL.add([" foo >=1.2 "])
        @test occursin("foo", status())
        @test occursin("(>=1.2)", status())

        # rm
        CondaPkg.PkgREPL.rm([" foo "])
        @test !occursin("foo", status())

        # add channel
        CondaPkg.PkgREPL.add([" foo-channel "], mode=:channel)
        @test occursin("foo-channel", status())

        # rm channel
        CondaPkg.PkgREPL.rm([" foo-channel "], mode=:channel)
        @test !occursin("foo-channel", status())

        # add pip
        CondaPkg.PkgREPL.add([" foo ~=1.3 "], mode=:pip)
        @test occursin("foo", status())
        @test occursin("(~=1.3)", status())

        # rm pip
        CondaPkg.PkgREPL.rm([" foo "], mode=:pip)
        @test !occursin("foo", status())

        # status
        # TODO: capture the output and check it equals status()
        CondaPkg.PkgREPL.status()

        # resolve
        CondaPkg.PkgREPL.resolve()

        # gc
        testgc && CondaPkg.PkgREPL.gc()

        # run
        # TODO: capture the output and check it contains "Python 3.10.2"
        CondaPkg.PkgREPL.run(["python", "--version"])
    end

end
