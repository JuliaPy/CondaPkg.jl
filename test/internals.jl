@testitem "PkgSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.PkgSpec("")
    @test_throws Exception CondaPkg.PkgSpec("foo!")
    @test_throws Exception CondaPkg.PkgSpec("foo", version="foo")
    spec = CondaPkg.PkgSpec("  F...OO_-0  ", version="  =1.2.3  ", channel="  SOME_chaNNEL  ")
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
    @test_throws Exception CondaPkg.PipPkgSpec("foo", version="1.2")
    spec = CondaPkg.PipPkgSpec("  F...OO_-0  ", version="  @./SOME/Path  ")
    @test spec.name == "f-oo-0"
    @test spec.version == "@./SOME/Path"
end

@testitem "meta IO" begin
    include("setup.jl")
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
