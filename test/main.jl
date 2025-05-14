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
    CondaPkg.add("python", version = "==3.10.2")
    isnull || CondaPkg.withenv() do
        pythonpath =
            joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
        @test isfile(pythonpath)
    end
    @test occursin("python", status())
end

@testitem "install/remove python package" begin
    include("setup.jl")
    CondaPkg.add("python", version = "==3.10.2")
    # verify package isn't already installed
    @test !occursin("six", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import six"`)
    end

    # install package
    CondaPkg.add("six", version = "==1.16.0")
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
    CondaPkg.add("python", version = "==3.10.2")
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
        CondaPkg.add("python", version = "==3.10.2")
        if kind == "uv"
            # TODO: there is an explicit flag for this now
            CondaPkg.add("uv")
        end
        # verify package isn't already installed
        @test !occursin("six", status())
        CondaPkg.withenv() do
            isnull || @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add_pip("six", version = "==1.16.0")
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

@testitem "pip install/remove python package with extras" begin
    include("setup.jl")
    CondaPkg.add("python", version = "==3.10.2")

    # verify package isn't already installed
    @test !occursin("pydantic", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import pydantic"`)
    end

    # install package without extras
    CondaPkg.add_pip("pydantic", version = "==2.9.2")
    @test occursin("pydantic", status())
    @test occursin("(==2.9.2)", status())
    CondaPkg.withenv() do
        isnull || run(`python -c "import pydantic"`)
        # fails on Windows sometimes - not sure why
        # probably email-validator is still installed from an earlier test
        isnull ||
            Sys.iswindows() ||
            @test_throws Exception run(`python -c "import email_validator"`)
    end
    @test occursin("v2.9.2", status()) == !isnull

    # install package with extras
    CondaPkg.add_pip("pydantic", version = "==2.9.2", extras = ["email"])
    @test occursin("pydantic", status())
    @test occursin("(==2.9.2, [email])", status())
    CondaPkg.withenv() do
        isnull || run(`python -c "import pydantic"`)
        isnull || run(`python -c "import email_validator"`)
    end
    @test occursin("v2.9.2", status()) == !isnull

    # remove package
    CondaPkg.rm_pip("pydantic")
    @test !occursin("pydantic", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import pydantic"`)
    end
end

@testitem "pip install/remove a local python package" begin
    include("setup.jl")
    CondaPkg.add("python", version="==3.10.2")
    # verify package isn't already installed
    @test !occursin("foo", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import foo"`)
    end

    # install package
    # The directory with the setup.py file (here `Foo`) needs to be different from the name of the Python module (here `foo`), otherwise `import foo` will never throw an exception and the tests checking that the package isn't installed will fail.
    pkg_path = joinpath(dirname(@__FILE__), "FooNonEditable")
    CondaPkg.add_pip("foononeditable", version="@ $(pkg_path)")
    @test occursin("foononeditable", status())
    @test occursin(pkg_path, status())
    CondaPkg.withenv() do
        isnull || run(`python -c "import foononeditable"`)
    end

    # remove package
    CondaPkg.rm_pip("foononeditable")
    @test !occursin("foononeditable", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import foononeditable"`)
    end
end

@testitem "pip install/remove a local editable python package" begin
    include("setup.jl")
    CondaPkg.add("python", version="==3.10.2")
    # verify package isn't already installed
    @test !occursin("foo", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import foo"`)
    end

    # install package
    # The directory with the setup.py file (here `Foo`) needs to be different from the name of the Python module (here `foo`), otherwise `import foo` will never throw an exception and the tests checking that the package isn't installed will fail.
    pkg_path = joinpath(dirname(@__FILE__), "Foo")
    CondaPkg.add_pip("foo", version="@ $(pkg_path)", editable=true)
    @test occursin("foo", status())
    @test occursin(pkg_path, status())
    CondaPkg.withenv() do
        isnull || run(`python -c "import foo"`)
    end

    # The `added` module shouldn't exist.
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import foo.added"`)
    end

    # Now add the `added.py` file to create the `added` module.
    added_src_path = joinpath(dirname(@__FILE__), "Foo", "foo", "test", "added.py")
    added_dst_path = joinpath(dirname(@__FILE__), "Foo", "foo", "added.py")
    cp(added_src_path, added_dst_path)

    # Test that the `added` module exists.
    CondaPkg.withenv() do
        isnull || run(`python -c "import foo.added; print(foo.added.y)"`)
    end

    # Remove the added file for later tests.
    rm(added_dst_path)

    # remove package
    CondaPkg.rm_pip("foo")
    @test !occursin("foo", status())
    CondaPkg.withenv() do
        isnull || @test_throws Exception run(`python -c "import foo"`)
    end
end

@testitem "install/remove libstdcxx-ng" begin
    include("setup.jl")
    CondaPkg.add("libstdcxx-ng", version = "<=julia", resolve = false)
    CondaPkg.resolve(force = true)
    CondaPkg.rm("libstdcxx-ng", resolve = false)
    CondaPkg.resolve(force = true)
    @test true
end

@testitem "install/remove openssl" begin
    include("setup.jl")
    CondaPkg.add("openssl", version = "<=julia", resolve = false)
    CondaPkg.resolve(force = true)
    CondaPkg.rm("openssl", resolve = false)
    CondaPkg.resolve(force = true)
    @test true
end

@testitem "install non-existent package" begin
    include("setup.jl")

    if !isnull
        # First add a package to ensure we are in a resolved state
        CondaPkg.add("python", version = "==3.10.2")

        # Verify clean state
        @test !occursin("Not Resolved", status())
        @test !occursin("nonexistentpackage123xyz", status())
        @test occursin("python", status())

        # Try to add non-existent package and verify it throws
        @test_throws Exception CondaPkg.add("nonexistentpackage123xyz")

        # Verify that resolving failed
        @test !CondaPkg.STATE.resolved

        # is_resolved() re-checks that the old deps are still valid (except Pixi)
        @test CondaPkg.is_resolved() == !ispixi

        # Verify the deps file was reverted
        @test !occursin("nonexistentpackage123xyz", status())
        @test occursin("python", status())
    end
end

@testitem "external conda env" begin
    include("setup.jl")
    dn = string(tempname(), backend, Sys.KERNEL, VERSION)
    if !isnull && !ispixi
        CondaPkg.STATE.test_preferences["env"] = dn
        # create empty env
        CondaPkg.resolve()
        @test !occursin("ca-certificates", status())
        # add a package to specs and install it
        CondaPkg.add("ca-certificates"; interactive = true, force = true)  # force: spurious windows failures
        @test occursin("ca-certificates", status())
        CondaPkg.withenv() do
            @test isfile(
                CondaPkg.envdir(Sys.iswindows() ? "Library" : "", "ssl", "cacert.pem"),
            )
        end
        # remove a package from specs, it must remain installed because we use a shared centralized env
        CondaPkg.rm("ca-certificates"; interactive = true, force = true)
        @test !occursin("ca-certificates", status())  # removed from specs ...
        CondaPkg.withenv() do  # ... but still installed (shared env might be used by specs from alternate julia versions)
            @test isfile(
                CondaPkg.envdir(Sys.iswindows() ? "Library" : "", "ssl", "cacert.pem"),
            )
        end
    end
end

@testitem "shared env" begin
    include("setup.jl")
    if !isnull && !ispixi
        CondaPkg.STATE.test_preferences["env"] = "@my_env"
        CondaPkg.add("python"; force = true)
        @test CondaPkg.envdir() ==
              joinpath(Base.DEPOT_PATH[1], "conda_environments", "my_env")
        @test isfile(CondaPkg.envdir(Sys.iswindows() ? "python.exe" : "bin/python"))
    end
    if !isnull && !ispixi
        CondaPkg.STATE.test_preferences["env"] = "@/some/absolute/path"
        @test_throws ErrorException CondaPkg.add("python"; force = true)
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
    @test_throws Exception CondaPkg.add("valid-package", version = "*invalid*version*")
    @test_throws Exception CondaPkg.add_pip("valid-package", version = "*invalid*version*")
    @test_throws Exception CondaPkg.add_channel("")
    @test !occursin("valid", status())
end
