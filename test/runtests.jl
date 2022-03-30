using CondaPkg
using Test

# Only run the gc tests on CI (because it's annoying to do it locally)
const testgc = get(ENV, "CI", "") == "true"

# output more than usual when testing
ENV["JULIA_CONDAPKG_VERBOSITY"] = "0"

status() = sprint(io -> CondaPkg.status(io=io))

const backend = get(ENV, "JULIA_CONDAPKG_BACKEND", "MicroMamba")

const isnull = backend == "Null"

@testset "CondaPkg" begin

    @testset "internals" begin

        @testset "PkgSpec" begin
            @test_throws Exception CondaPkg.PkgSpec("")
            @test_throws Exception CondaPkg.PkgSpec("foo!")
            @test_throws Exception CondaPkg.PkgSpec("foo", version="foo")
            spec = CondaPkg.PkgSpec("  F...OO_-0  ", version="  =1.2.3  ", channel="  SOME_chaNNEL  ")
            @test spec.name == "f...oo_-0"
            @test spec.version == "=1.2.3"
            @test spec.channel == "SOME_chaNNEL"
        end

        @testset "ChannelSpec" begin
            @test_throws Exception CondaPkg.ChannelSpec("")
            spec = CondaPkg.ChannelSpec("  SOME_chaNNEL  ")
            @test spec.name == "SOME_chaNNEL"
        end

        @testset "PipPkgSpec" begin
            @test_throws Exception CondaPkg.PipPkgSpec("")
            @test_throws Exception CondaPkg.PipPkgSpec("foo!")
            @test_throws Exception CondaPkg.PipPkgSpec("foo", version="1.2")
            spec = CondaPkg.PipPkgSpec("  F...OO_-0  ", version="  @./SOME/Path  ")
            @test spec.name == "f-oo-0"
            @test spec.version == "@./SOME/Path"
        end

        @testset "meta IO" begin
            specs = Any[
                CondaPkg.PkgSpec("foo", version="=1.2.3", channel="bar"),
                CondaPkg.ChannelSpec("fooo"),
                CondaPkg.PipPkgSpec("foooo", version="==2.3.4")
            ]
            for spec in specs
                io = IOBuffer()
                CondaPkg.write_meta(io, spec)
                seekstart(io)
                spec2 = CondaPkg.read_meta(io, typeof(spec))
                @test spec == spec2
                for k in propertynames(spec)
                    @test getproperty(spec, k) == getproperty(spec2, k)
                end
            end
        end

        @testset "abspathurl" begin
            @test startswith(CondaPkg.abspathurl("foo"), "file://")
            @test endswith(CondaPkg.abspathurl("foo"), "/foo")
            if Sys.iswindows()
                @test CondaPkg.abspathurl("D:\\Foo\\bar.TXT") == "file:///D:/Foo/bar.TXT"
            else
                @test CondaPkg.abspathurl("/Foo/bar.TXT") == "file:///Foo/bar.TXT"
            end
        end

    end

    isnull && @testset "Null backend" begin
        @test CondaPkg.backend() == :Null
        @test CondaPkg.activate!(copy(ENV)) == ENV
        @test occursin("Null", status())
        @test_throws ErrorException CondaPkg.envdir()
    end

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
        isnull || CondaPkg.withenv() do
            pythonpath = joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
            @test isfile(pythonpath)
        end
        @test occursin("python", status())
    end

    @testset "install/remove python package" begin
        # verify package isn't already installed
        @test !occursin("six", status())
        CondaPkg.withenv() do
            isnull || @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add("six", version="==1.16.0")
        @test occursin("six", status())
        @test occursin("(==1.16.0)", status())
        CondaPkg.withenv() do
            isnull || run(`python -c "import six"`)
        end
        @test occursin("v1.16.0", status()) == !isnull

        # remove package
        CondaPkg.rm("six")
        @test !occursin("six", status())
        CondaPkg.withenv() do
            isnull || @test_throws Exception run(`python -c "import six"`)
        end
    end

    @testset "pip install/remove python package" begin
        # verify package isn't already installed
        @test !occursin("six", status())
        CondaPkg.withenv() do
            isnull || @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add_pip("six", version="==1.16.0")
        @test occursin("six", status())
        @test occursin("(==1.16.0)", status())
        CondaPkg.withenv() do
            isnull || run(`python -c "import six"`)
        end
        @test occursin("v1.16.0", status()) == !isnull

        # remove package
        CondaPkg.rm_pip("six")
        @test !occursin("six", status())
        CondaPkg.withenv() do
            isnull || @test_throws Exception run(`python -c "import six"`)
        end
    end


    isnull || @testset "install/remove executable package" begin
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
        CondaPkg.PkgREPL.add(["  six ==1.16.0 "])
        @test occursin("six", status())
        @test occursin("(==1.16.0)", status())

        # rm
        CondaPkg.PkgREPL.rm([" six "])
        @test !occursin("six", status())

        # add channel
        CondaPkg.PkgREPL.channel_add([" numba "])
        @test occursin("numba", status())

        # rm channel
        CondaPkg.PkgREPL.channel_rm([" numba "])
        @test !occursin("numba", status())

        # add pip
        CondaPkg.PkgREPL.pip_add([" six ==1.16.0 "])
        @test occursin("six", status())
        @test occursin("(==1.16.0)", status())

        # rm pip
        CondaPkg.PkgREPL.pip_rm([" six "])
        @test !occursin("six", status())

        # status
        # TODO: capture the output and check it equals status()
        CondaPkg.PkgREPL.status()

        # resolve
        CondaPkg.PkgREPL.resolve()

        # gc
        testgc && CondaPkg.PkgREPL.gc()

        # run
        # TODO: capture the output and check it contains "Python 3.10.2"
        isnull || CondaPkg.PkgREPL.run(["python", "--version"])
    end

end
