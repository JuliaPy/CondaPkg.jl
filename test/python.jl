@testitem "Python provider conventions" begin
    S = CondaPkg.PkgSpec
    channels = [CondaPkg.ChannelSpec("conda-forge")]
    function deps(specs...)
        packages = Dict{String,Dict{String,S}}()
        for (i, spec) in enumerate(specs)
            get!(Dict{String,S}, packages, spec.name)[string(i)] = spec
        end
        packages
    end
    marked = S("libpython"; channel = "conda-forge", build = "**bundled-or-separate**")
    function resolve(specs...; linux = true)
        packages = deps(specs...)
        CondaPkg._resolve_libpython!(packages; linux)
        CondaPkg._resolve_python!(packages, channels)
        Dict(p.name => p for p in CondaPkg._resolve_merge_packages(packages, channels))
    end
    @testset "numeric constraints" begin
        for version in ["<15", "<=14.9", "14.*", "==14.2", ">=3.4,<15.0", "<14|<15", "<20,<=14"]
            @test CondaPkg._resolve_excludes_libstdcxx15(version)
        end
        for version in ["", "*", "<=15", "<15.1", ">=15", "<15|>=16", "!=15", raw"^14$", "<15.*"]
            @test !CondaPkg._resolve_excludes_libstdcxx15(version)
        end
    end
    @testset "fallback and platforms" begin
        for name in ["libstdcxx", "libstdcxx-ng"], channel in ["", "conda-forge"]
            runtime = S(name; version = ">=3.4,<15", channel)
            result = resolve(S("python"), marked, runtime)
            @test !haskey(result, "libpython")
            @test result["python"] == S("python"; channel = "conda-forge", version = "<3.15.0a0")
            result = resolve(S("python"), marked, runtime; linux = false)
            @test result["libpython"] == S("libpython"; channel = "conda-forge")
            @test result["python"].version == ""
        end
        for runtime in [S("libstdcxx"; version = "<=15.1"), S("libstdcxx"; version = "<15", channel = "anaconda")]
            @test haskey(resolve(S("python"), marked, runtime), "libpython")
        end
        @test haskey(resolve(S("python"), marked), "libpython")
    end
    @testset "preserve explicit requirements and intersections" begin
        result = resolve(S("python"; version = "3.13.*|>=3.15", build = "**cpython**"),
            marked, S("libpython"; version = ">=3.13"), S("libstdcxx"; version = "<15"))
        @test result["libpython"].version == ">=3.13"
        # Dict iteration can put the synthetic constraint before or after the original.
        alternatives = Set(Set(strip.(split(part, ','))) for part in split(result["python"].version, '|'))
        @test alternatives == Set([Set(["3.13.*", "<3.15.0a0"]), Set([">=3.15", "<3.15.0a0"])])
        @test result["python"].build == "*cp*"
    end
    @testset "preserve file-sourced Python specs" begin
        for linux in [true, false]
            original = S("python"; version = ">=3.12", build = "**cpython**")
            packages = deps(original, marked, S("libstdcxx"; version = "<15"))
            CondaPkg._resolve_libpython!(packages; linux)
            @test packages["python"]["1"] == original
            @test length(packages["python"]) == 2
            @test packages["python"]["<internal:libpython>"] == S(
                "python"; channel = "conda-forge", version = linux ? "<3.15.0a0" : "",
            )
        end
    end
    @testset "channel checks" begin
        @test_throws ErrorException resolve(marked)
        @test_throws ErrorException resolve(S("python"; channel = "anaconda"), marked)
        @test_throws ErrorException resolve(S("python"), S("python"; channel = "anaconda"), marked)
        for channel in ["", "anaconda"]
            @test_throws ErrorException resolve(S("python"), S(marked; channel))
        end
        ordinary = S("libpython"; channel = "anaconda")
        @test resolve(S("python"; channel = "anaconda"), ordinary)["libpython"] == ordinary
        packages = deps(S("python"), marked)
        CondaPkg._resolve_libpython!(packages; linux = false)
        CondaPkg._resolve_python!(packages, channels)
        mapped_channels = copy(channels)
        CondaPkg._resolve_map_channels!(mapped_channels, packages, Dict("conda-forge" => "mirror"))
        @test all(p.channel == "mirror" for p in CondaPkg._resolve_merge_packages(packages, mapped_channels))
    end
    @testset "CPython providers" begin
        for (channel, build) in [("conda-forge", "*cp*"), ("anaconda", ""), ("pkgs/main", "")]
            @test resolve(S("python"; channel, build = "**cpython**"))["python"].build == build
        end
    end
end

@testitem "install PythonCall dependencies" begin
    include("setup.jl")
    # Resolve the actual combination through file discovery, <=julia expansion,
    # marker handling, and the backend solver, using this Julia's runtime bounds.
    source = read(joinpath(@__DIR__, "data", "pythoncall", "CondaPkg.toml"), String)
    write(CondaPkg.cur_deps_file(), source)
    @test CondaPkg.resolve(force = true) === nothing
    @test read(CondaPkg.cur_deps_file(), String) == source
    if !isnull
        installed = CondaPkg.current_packages()
        python_version = VersionNumber(installed["python"].version)
        @test v"3.10" <= python_version < v"4"
        fallback = Sys.islinux() && any(
            bound !== nothing && CondaPkg._resolve_excludes_libstdcxx15(bound)
            for bound in (
                CondaPkg._compatible_libstdcxx_version(),
                CondaPkg._compatible_libstdcxx_ng_version(),
            )
        )
        meta = open(CondaPkg.read_meta, joinpath(CondaPkg.STATE.meta_dir, "meta"))
        @test any(p -> p.name == "libpython", meta.packages) == !fallback
        if fallback
            @test python_version < v"3.15.0-DEV"
        else
            @test haskey(installed, "libpython")
        end
        # Check the installed interpreter is CPython and its shared library is
        # present and loadable, whether supplied by python or libpython. Use a
        # subprocess so loading another Python cannot affect later Julia tests.
        script = raw"""
        import ctypes, os, platform, sys, sysconfig
        assert platform.python_implementation() == "CPython"
        if sys.platform == "win32":
            suffix = "t" if sysconfig.get_config_var("Py_GIL_DISABLED") else ""
            library = os.path.join(sys.base_prefix, f"python{sys.version_info.major}{sys.version_info.minor}{suffix}.dll")
        else:
            library = os.path.join(sysconfig.get_config_var("LIBDIR"), sysconfig.get_config_var("LDLIBRARY"))
        assert os.path.isfile(library), library
        lib = ctypes.CDLL(library)
        lib.Py_GetVersion.restype = ctypes.c_char_p
        assert lib.Py_GetVersion().decode().startswith(platform.python_version())
        import ssl
        """
        CondaPkg.withenv() do
            @test success(`python -c $script`)
        end
    end
end
