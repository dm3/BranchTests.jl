# Branch Tests

Branch tests will help you write tests for sequences of state transitions!

`BranchTests` offers a single test macro - `@testbranch`. The name was chosen
to sound like `@testset` - `@testbranch`s close cousin. The macro accepts all
the same arguments as `@testset` does.

Let's start with a motivating example:

```
@testbranch "Vector" begin
    v = Vector{Int}()
    @test isempty(v)

    @testbranch "adds one element" begin
        push!(v, 1)
        @test length(v) == 1

        @testbranch "adds another element" begin
            push!(v, 2)
            @test length(v) == 2
        end

        @testbranch "removes element" begin
            pop!(v)
            @test isempty(v)
        end
    end
end
```

Running the above produces:

```
Test Summary: | Pass  Total
Vector        |    3      3
Test Summary: | Pass  Total
Vector        |    3      3
```

The `"Vector"` test branch has been run two times. Once for every terminating
test leaf of the test set. Notice how the additional element pushed into `v`
inside the `"adds another element"` test branch didn't affect the `@test` in
the `"removes element"` test branch? That's how `@testbranch` differs from
a bare `@testset`.

Let's add a failing `@test` in the leaf:

```
@testbranch "Vector" begin
    v = Vector{Int}()
    @test isempty(v)

    @testbranch "adds one element" begin
        push!(v, 1)
        @test length(v) == 1

        @testbranch "adds another element" begin
            push!(v, 2)
            @test length(v) == 1                  # FAIL: should be 2
        end

        @testbranch "removes element" begin
            pop!(v)
            @test isempty(v)
        end
    end
end
```

Result:

```
adds another element: Test Failed at REPL[9]:11
  Expression: length(v) == 1
   Evaluated: 2 == 1
Stacktrace:
 [1] macro expansion at ./REPL[9]:11 [inlined]
 [2] macro expansion at /projects/BranchTests/src/BranchTests.jl:216 [inlined]
 [3] macro expansion at /usr/share/julia/stdlib/v1.5/Test/src/Test.jl:1115 [inlined]
 ...
 [12] (::var"#11#12")(::BranchTests.Run) at /projects/BranchTests/src/BranchTests.jl:216
Test Summary:            | Pass  Fail  Total
Vector                   |    2     1      3
  adds one element       |    1     1      2
    adds another element |          1      1
┌ Error: Some tests did not pass: 2 passed, 1 failed, 0 errored, 0 broken.
└ @ BranchTests /projects/BranchTests/src/BranchTests.jl:148
Test Summary: | Pass  Total
Vector        |    3      3
```

Now we see there was a `@test` failure and a Pass result! The fact that the
`"adds another element"` leaf test failed did not stop the `"removes element"`
test from passing.

Let's fail the non-leaf branch now:

```
@testbranch "Vector" begin
    v = Vector{Int}()
    @test isempty(v)

    @testbranch "adds one element" begin
        push!(v, 1)
        @test length(v) == 2              # FAIL: should be 1

        @testbranch "adds another element" begin
            push!(v, 2)
            @test length(v) == 2
        end

        @testbranch "removes element" begin
            pop!(v)
            @test isempty(v)
        end
    end
end
```

Result:

```
adds one element: Test Failed at REPL[10]:7
  Expression: length(v) == 2
   Evaluated: 1 == 2
Stacktrace:
 [1] macro expansion at ./REPL[10]:7 [inlined]
 [2] macro expansion at /projects/BranchTests/src/BranchTests.jl:216 [inlined]
 [3] macro expansion at /usr/share/julia/stdlib/v1.5/Test/src/Test.jl:1115 [inlined]
 ...
 [8] (::var"#13#14")(::BranchTests.Run) at /projects/BranchTests/src/BranchTests.jl:216
Test Summary:      | Pass  Fail  Total
Vector             |    1     1      2
  adds one element |          1      1
┌ Error: Some tests did not pass: 1 passed, 1 failed, 0 errored, 0 broken.
└ @ BranchTests /projects/BranchTests/src/BranchTests.jl:148
```

We see that both leaves of the `"Vector"` branch test failed to run because the
branch they're rooted on has failed.

## How it works

The `@testbranch` macro generates a function with `@testset` macros and some
flow control inside. The function then runs repeatedly while tracking the
branch pass/fail results.

TestBranch isn't in any way an original idea. I've got the idea from the C++
testing framework [Catch2](https://github.com/catchorg/Catch2/blob/devel/docs/tutorial.md#test-cases-and-sections).

## TODO

### Tear down

Julia doesn't have deterministic destruction which could be used for after-test
cleanup. I haven't really thought of a nice solution yet. Ideas welcome!

### Better result printout

Currently, running

```
@testbranch "Vector" begin
    v = Vector{Int}()
    @test isempty(v)

    @testbranch "adds one element" begin
        push!(v, 1)
        @test length(v) == 1
    end

    @testbranch "equality" begin
        @test v == v
    end
end
```

will print

```
Test Summary: | Pass  Total
Vector        |    2      2
Test Summary: | Pass  Total
Vector        |    2      2
```

I'd like to see

```
Test Summary:             | Pass  Total
Vector - adds one element |    2      2
Test Summary:             | Pass  Total
Vector - equality         |    2      2
```

Every root test branch description should be suffixed by the test branch leaf
which passed.  This can _probably_ be done when the underlying `TestSet` is a
`Test.DefaultTestSet` by modifying the `description` field before it's printed
out. It is a hack though, so I'd prefer any better idea!
