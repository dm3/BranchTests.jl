using BranchTests
using Test

Code = quote
    @testbranch "Vector" begin
        println("in 'Vector'")
        v = Vector{Int}()
        @test isempty(v)

        @testbranch "adds one element" begin
            println("in 'adds one element'")
            push!(v, 1)
            @test length(v) == 1

            @testbranch "adds another element" begin
                println("in 'adds another element'")
                push!(v, 2)
                @test length(v) == 2
            end

            @testbranch DefaultTestSet "removes one" begin # test set type
                println("in 'removes one'")
                pop!(v)
                @test isempty(v)
            end
        end

        @testbranch begin # no name
            println("in 'equality'")
            @test v == v
        end
    end
end

eval(Code)

#@testset "vector" begin
#    v = Vector{Int}()
#
#    @testset "adds one element" begin
#        push!(v, 1)
#        @test length(v) == 1
#
#        @testset "adds another element" begin
#            push!(v, 1)
#            @test length(v) == 2
#        end
#
#        @testset "removes - empty" begin
#            pop!(v)
#            @test isempty(v)
#        end
#    end
#end
