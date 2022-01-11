using CondaPkg
using Test

@testset "CondaPkg" begin

    @testset "add/remove channel" begin
        @test !occursin("conda-forge", sprint(CondaPkg.status))
        CondaPkg.add_channel("conda-forge")
        @test occursin("conda-forge", sprint(CondaPkg.status))
        CondaPkg.rm_channel("conda-forge")
        @test !occursin("conda-forge", sprint(CondaPkg.status))
    end

    @testset "install python" begin
        @test !occursin("python", sprint(CondaPkg.status))
        CondaPkg.add("python")
        CondaPkg.resolve()
        CondaPkg.withenv() do
            pythonpath = joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
            @test isfile(pythonpath)
        end
        @test occursin("python", sprint(CondaPkg.status))
    end

    @testset "install/remove python package" begin
        # verify package isn't already installed
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add("six")
        CondaPkg.withenv() do
            run(`python -c "import six"`)
        end

        # remove package
        CondaPkg.rm("six")
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end
    end

    @testset "pip install/remove python package" begin
        # verify package isn't already installed
        CondaPkg.withenv() do
            @test_throws Exception run(`python -c "import six"`)
        end

        # install package
        CondaPkg.add_pip("six")
        CondaPkg.withenv() do
            run(`python -c "import six"`)
        end

        # remove package
        CondaPkg.rm_pip("six")
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

    
    @testset "clean()" begin
        # verify that clean runs without errors
        CondaPkg.clean()
    end

end
