@testset "Null backend" begin
    @test CondaPkg.backend() == :Null
    let e = copy(ENV)
        @test CondaPkg.activate!(e) == ENV
    end

    @test startswith(status(), "Backend is 'Null'")
    @test_throws ErrorException CondaPkg.envdir()
    
end