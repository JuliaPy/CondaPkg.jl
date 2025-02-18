@testitem "PkgSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.PkgSpec("")
    @test_throws Exception CondaPkg.PkgSpec("foo!")
    @test_throws Exception CondaPkg.PkgSpec("foo", version = "foo")
    spec = CondaPkg.PkgSpec(
        "  F...OO_-0  ",
        version = "  =1.2.3  ",
        channel = "  SOME_chaNNEL  ",
    )
    @test spec.name == "f...oo_-0"
    @test spec.version == "=1.2.3"
    @test spec.channel == "SOME_chaNNEL"
end

@testitem "ChannelSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.ChannelSpec("")
    spec = CondaPkg.ChannelSpec("  SOME_chaNNEL  ")
    @test spec.name == "SOME_chaNNEL"
end

@testitem "PipPkgSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.PipPkgSpec("")
    @test_throws Exception CondaPkg.PipPkgSpec("foo!")
    @test_throws Exception CondaPkg.PipPkgSpec("foo", version = "1.2")
    spec = CondaPkg.PipPkgSpec("  F...OO_-0  ", version = "  @./SOME/Path  ")
    @test spec.name == "f-oo-0"
    @test spec.version == "@./SOME/Path"
end

@testitem "meta IO" begin
    include("setup.jl")
    specs = Any[
        CondaPkg.PkgSpec("foo", version = "=1.2.3", channel = "bar"),
        CondaPkg.ChannelSpec("fooo"),
        CondaPkg.PipPkgSpec("foooo", version = "==2.3.4"),
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

@testitem "abspathurl" begin
    include("setup.jl")
    @test startswith(CondaPkg.abspathurl("foo"), "file://")
    @test endswith(CondaPkg.abspathurl("foo"), "/foo")
    if Sys.iswindows()
        @test CondaPkg.abspathurl("D:\\Foo\\bar.TXT") == "file:///D:/Foo/bar.TXT"
    else
        @test CondaPkg.abspathurl("/Foo/bar.TXT") == "file:///Foo/bar.TXT"
    end
end

@testitem "_resolve_merge_versions" begin
    include("setup.jl")
    @testset "$(case.v1) $(case.v2)" for case in [
        (v1 = "1.2.3", v2 = "1.2.3", expected = "1.2.3, 1.2.3"),
        (v1 = "1.2.3", v2 = "1.2.4", expected = "1.2.3, 1.2.4"),
        (v1 = "1.2.3", v2 = ">=1.2,<2", expected = "1.2.3, >=1.2,<2"),
        (v1 = ">=1.2,<2", v2 = ">=2.1,<3", expected = ">=1.2,<2, >=2.1,<3"),
        (v1 = "1|2", v2 = "2|3", expected = "1, 2 | 1, 3 | 2, 2 | 2, 3"),
    ]
        @test CondaPkg._resolve_merge_versions(case.v1, case.v2) == case.expected
    end
end

@testitem "_compatible_libstdcxx_ng_version" begin
    include("setup.jl")
    key = "JULIA_CONDAPKG_LIBSTDCXX_NG_VERSION"
    orig_bound = pop!(ENV, key, nothing)
    try
        @testset "$new_bound" for new_bound in [nothing, "", "foo"]
            if new_bound === nothing
                delete!(ENV, key)
            else
                ENV[key] = new_bound
            end
            bound = CondaPkg._compatible_libstdcxx_ng_version()
            if new_bound === nothing || new_bound == ""
                if Sys.islinux()
                    if bound !== nothing
                        @test bound isa String
                        @test startswith(bound, ">=")
                    end
                else
                    @test bound === nothing
                end
            else
                @test bound == new_bound
            end
        end
    finally
        if orig_bound === nothing
            delete!(ENV, key)
        else
            ENV[key] = orig_bound
        end
    end
end

@testitem "_compatible_openssl_version" begin
    include("setup.jl")
    key = "JULIA_CONDAPKG_OPENSSL_VERSION"
    orig_bound = pop!(ENV, key, nothing)
    try
        @testset "$new_bound" for new_bound in [nothing, "", "foo"]
            if new_bound === nothing
                delete!(ENV, key)
            else
                ENV[key] = new_bound
            end
            bound = CondaPkg._compatible_openssl_version()
            if new_bound === nothing || new_bound == ""
                if bound !== nothing
                    @test bound isa String
                    @test startswith(bound, ">=")
                end
            else
                @test bound == new_bound
            end
        end
    finally
        if orig_bound === nothing
            delete!(ENV, key)
        else
            ENV[key] = orig_bound
        end
    end
end
