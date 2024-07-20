@testitem "resolve (empty)" begin
    include("setup.jl")
    @test CondaPkg.resolve() === nothing
    @test occursin("(empty)", status())
end

@testitem "Null backend" begin
    include("setup.jl")
    if isnull
        @test CondaPkg.backend() == :Null
        @test CondaPkg.activate!(copy(ENV)) == ENV
        @test occursin("Null", status())
        @test_throws ErrorException CondaPkg.envdir()
    else
        @test true
    end
end

@testitem "add/remove channel" begin
    include("setup.jl")
    @test !occursin("conda-forge", status())
    CondaPkg.add_channel("conda-forge")
    @test occursin("conda-forge", status())
    CondaPkg.rm_channel("conda-forge")
    @test !occursin("conda-forge", status())
end

@testitem "install python" begin
    include("setup.jl")
    @test !occursin("python", status())
    CondaPkg.add("python", version="==3.10.2")
    isnull || CondaPkg.withenv() do
        pythonpath = joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
        @test isfile(pythonpath)
    end
    @test occursin("python", status())
end

@testitem "install/remove python package" begin
    include("setup.jl")
    CondaPkg.add("python", version="==3.10.2")
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

@testitem "install/remove multiple python packages" begin
    include("setup.jl")
    CondaPkg.add("python", version="==3.10.2")
    # verify package isn't already installed
    @test !occursin("jsonlines ", status())
    @test !occursin("cowpy", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import jsonlines"`)
        isnull || @test_throws Exception run(`python -c "import cowpy"`)
    end

    # install multiple packages
    CondaPkg.add(["jsonlines", "cowpy"])
    @test occursin("jsonlines", status())
    @test occursin("cowpy", status())

    # remove multiple packages
    CondaPkg.rm(["jsonlines", "cowpy"])
    @test !occursin("jsonlines ", status())
    @test !occursin("cowpy", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import jsonlines"`)
        isnull || @test_throws Exception run(`python -c "import cowpy"`)
    end
end

@testitem "pip install/remove python package" begin
    @testset "using $kind" for kind in ["pip", "uv"]
        include("setup.jl")
        CondaPkg.add("python", version="==3.10.2")
        if kind == "uv"
            CondaPkg.add("uv")
        end
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
end

@testitem "install/remove executable package" begin
    include("setup.jl")
    if !isnull
        CondaPkg.add("curl", resolve=false)
        CondaPkg.resolve(force=true)
        curl_path = CondaPkg.which("curl")
        @test curl_path !== nothing
        @test isfile(curl_path)
        CondaPkg.rm("curl", resolve=false)
        CondaPkg.resolve(force=true)
        @test !isfile(curl_path)
    end
end

@testitem "install/remove libstdcxx_ng" begin
    include("setup.jl")
    CondaPkg.add("libstdcxx-ng", version="<=julia", resolve=false)
    CondaPkg.resolve(force=true)
    CondaPkg.rm("libstdcxx-ng", resolve=false)
    CondaPkg.resolve(force=true)
    @test true
end

@testitem "install/remove opensll" begin
    include("setup.jl")
    CondaPkg.add("openssl", version="<=julia", resolve=false)
    CondaPkg.resolve(force=true)
    CondaPkg.rm("openssl", resolve=false)
    CondaPkg.resolve(force=true)
    @test true
end

@testitem "external conda env" begin
    include("setup.jl")
    dn = string(tempname(), backend, Sys.KERNEL, VERSION)
    isnull || withenv("JULIA_CONDAPKG_ENV" => dn) do
        # create empty env
        CondaPkg.resolve()
        @test !occursin("ca-certificates", status())
        # add a package to specs and install it
        CondaPkg.add("ca-certificates"; interactive=true, force=true)  # force: spurious windows failures
        @test occursin("ca-certificates", status())
        CondaPkg.withenv() do
            @test isfile(CondaPkg.envdir(Sys.iswindows() ? "Library" : "",  "ssl", "cacert.pem"))
        end
        # remove a package from specs, it must remain installed because we use a shared centralized env
        CondaPkg.rm("ca-certificates"; interactive=true, force=true)
        @test !occursin("ca-certificates", status())  # removed from specs ...
        CondaPkg.withenv() do  # ... but still installed (shared env might be used by specs from alternate julia versions)
            @test isfile(CondaPkg.envdir(Sys.iswindows() ? "Library" : "",  "ssl", "cacert.pem"))
        end
    end
end

@testitem "shared env" begin
    include("setup.jl")
    isnull || withenv("JULIA_CONDAPKG_ENV" => "@my_env") do
        CondaPkg.add("python"; force=true)
        @test CondaPkg.envdir() == joinpath(Base.DEPOT_PATH[1], "conda_environments", "my_env")
        @test isfile(CondaPkg.envdir(Sys.iswindows() ? "python.exe" : "bin/python"))
    end
    isnull || withenv("JULIA_CONDAPKG_ENV" => "@/some/absolute/path") do
        @test_throws ErrorException CondaPkg.add("python"; force=true)
    end
end

@testitem "update" begin
    include("setup.jl")
    CondaPkg.update()
    @test CondaPkg.is_resolved()
end

@testitem "gc" begin
    include("setup.jl")
    testgc && CondaPkg.gc()
    @test true
end

@testitem "validation" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.add("!invalid!package!")
    @test_throws Exception CondaPkg.add_pip("!invalid!package!")
    @test_throws Exception CondaPkg.add("valid-package", version="*invalid*version*")
    @test_throws Exception CondaPkg.add_pip("valid-package", version="*invalid*version*")
    @test_throws Exception CondaPkg.add_channel("")
    @test !occursin("valid", status())
end
