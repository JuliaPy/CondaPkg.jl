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
        @test result["python"].version == "3.13.*, <3.15.0a0 | >=3.15, <3.15.0a0"
        @test result["python"].build == "*cp*"
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
