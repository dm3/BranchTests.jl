module BranchTests

using Test

## Runtime

struct Tag
    name :: String
    idx :: Int
end
Base.show(io :: IO, v :: Tag) = print(io, "Tag[$(v.name)($(v.idx))]")

Base.@kwdef mutable struct Node
    parent   :: Union{Nothing, Node} = nothing
    children :: Vector{Node}         = []
    tag      :: Tag
end
function Base.show(io :: IO, v :: Node)
    print(io, "Node($(v.tag))[")
    if !isnothing(v.parent)
        print(io, "p=$(v.parent)")
    end
    if !isempty(v.children)
        print(io, "c={")
        for c in v.children
            print(io, c.tag)
            print(io, ",")
        end
        print(io, "}")
    end
    print(io, "]")
end

tag(n :: Node) = n.tag
is_branch(n :: Node) = !isempty(n.children)
is_leaf(n :: Node) = !is_branch(n)

function collect_children!(res, n :: Node)
    append!(res, n.children)
    for c in n.children
        collect_children!(res, c)
    end
end

# includes `n`
function descendants(n :: Node)
    res = []
    push!(res, n)
    collect_children!(res, n)
    res
end

function collect_parents!(res, n :: Node)
    if isnothing(n.parent)
        return
    end
    push!(res, n.parent)
    collect_parents!(res, n.parent)
end

# includes `n`
function ancestors(n :: Node)
    res = []
    push!(res, n)
    collect_parents!(res, n)
    res
end

function collect_leaves!(res, n :: Node)
    if isempty(n.children)
        push!(res, n)
    else
        for c in n.children
            collect_leaves!(res, c)
        end
    end
end

struct Tree
    root :: Node
end

function leaves(t :: Tree)
    res = []
    collect_leaves!(res, t.root)
    res
end

function node(t :: Tree, tag :: Tag)
    res = descendants(t.root)
    res[findfirst(n -> n.tag == tag, res)]
end

Base.@kwdef mutable struct Run
    tree     :: Tree
    failed   :: Set{Tag} = Set()
    finished :: Set{Tag} = Set()
end
Run(tree :: Tree) = Run(tree = tree)
Base.length(r :: Run) = length(leaves(r.tree))

function should_run(r :: Run, t :: Tag)
    n = node(r.tree, t)
    if isempty(intersect(map(tag, ancestors(n)), r.failed)) # not failed
        (is_branch(n) && !isempty(setdiff(map(tag, descendants(n)), r.finished))) || !(t in r.finished)
    else
        false
    end
end
should_run(r :: Run) = !isempty(setdiff(map(tag, leaves(r.tree)), union(r.failed, r.finished)))
failed!(r :: Run, t :: Tag) = union!(r.failed, map(tag, descendants(node(r.tree, t))))
finished!(r :: Run, t :: Tag) = push!(r.finished, t)

struct BranchTestSet{T <: Test.AbstractTestSet} <: Test.AbstractTestSet
    node    :: Tag
    testset :: T
end

BranchTestSet(desc :: AbstractString; node :: Expr, testsettype = Test.DefaultTestSet, kwargs...) =
    # TODO: what's the proper way to pass `node` as Tag instead of Expr to avoid `eval`?
    BranchTestSet{testsettype}(eval(node), testsettype(desc; kwargs...))

Test.record(ts :: BranchTestSet, t :: Test.AbstractTestSet) = Test.record(ts.testset, t)

function Test.record(ts :: BranchTestSet, t :: Union{Test.Broken, Test.Pass, Test.Fail, Test.Error})
    Test.record(ts.testset, t)
    if isa(t, Test.Fail) || isa(t, Test.Error)
        failed!(task_local_storage(:__TESTBRANCHRUN__), ts.node)
    end
    t
end

function Test.finish(ts :: BranchTestSet)
    finished!(task_local_storage(:__TESTBRANCHRUN__), ts.node)
    Test.finish(ts.testset)
end

function run(f, r :: Run)
    testsets = []
    try
        task_local_storage(:__TESTBRANCHRUN__, r)
        n = 0
        while should_run(r) && n <= length(r)
            n += 1
            push!(testsets, f(r))
        end
    finally
        task_local_storage(:__TESTBRANCHRUN__, nothing)
    end
    return testsets
end

## Macros

function parse_testbranch_args(args)
    ln = nothing
    name = nothing
    testsetargs = []
    for arg in args
        if isa(arg, Symbol) || (isa(arg, Expr) && arg.head === Symbol(".")) # (qualified) testset name
            push!(testsetargs, Expr(Symbol("="), :testsettype, arg))
        elseif isa(arg, LineNumberNode)
            ln = arg
        elseif isa(arg, AbstractString) #|| (isa(arg, Expr) && arg.head === :string) && name = esc(arg)
            # TODO: name should be a Union{String, Expr} or Expr
            name = arg
        elseif isa(arg, Expr) && arg.head === :(=)
            push!(testsetargs, arg)
        else
            error("Unexpected argument $arg to @testset")
        end
    end
    (ln, name, testsetargs)
end

function testbranch_expr(input_expr)
    node_idx = 1
    parent = nothing
    node_ = nothing
    root = nothing
    @gensym state_ done_

    process = expr -> begin
        if expr.head == :macrocall && expr.args[1] == Symbol("@testbranch")
            if length(expr.args) < 2
                error("Too few arguments to @testbranch: $(expr.args[1:end])")
            end

            (ln, name, testsetargs) = parse_testbranch_args(expr.args[2:end-1])
            name = isnothing(name) ? "branch test set" : name
            body = expr.args[end]
            tag = Tag(name, node_idx)
            node_idx += 1

            node_ = Node(parent = parent, tag = tag)
            if isnothing(root)
                root = node_
            end
            if !isnothing(parent)
                push!(parent.children, node_)
            end
            parent = node_

            new_body = process(body)

            node_ = parent
            if !isnothing(parent)
                parent = parent.parent
            end

            inner = quote
                Test.@testset BranchTestSet node=:(Tag($$(tag.name), $$(tag.idx))) $(testsetargs...) $name begin
                    try
                        $new_body
                    finally
                        $(if is_leaf(node_) quote $done_ = true end end)
                    end
                end
            end

            Expr(:block, ln, quote
                $(if isnothing(parent) quote local $done_ = false end end)
                if !$done_ && BranchTests.should_run($state_, $tag)
                    $(if isnothing(parent) Expr(:return, inner) else inner end)
                end
            end)
        else
            new_expr = copy(expr)
            for (idx, arg) in enumerate(expr.args)
                if isa(arg, Expr)
                    new_expr.args[idx] = process(arg)
                end
            end
            new_expr
        end
    end
    expr = process(input_expr)
    tree = BranchTests.Tree(root)
    testset_name = "Branches - $(root.tag.name)($(length(leaves(tree))))"
    quote
        $state_ = $tree
        Test.@testset $testset_name begin
            BranchTests.run(BranchTests.Run($state_)) do $state_
                $expr
            end
        end
    end
end

"""
@testbranch [CustomTestSet] [option=val  ...] ["description"] begin ... end

Starts a new test branch.

If no custom testset type is given it defaults to creating a
`Test.DefaultTestSet`. See `Test.@testset` documentation.

Returns an array of passing test sets.
"""
macro testbranch(args...)
    if args[end].head == :Expr
        error("Expected a begin..end block")
    end
    esc(testbranch_expr(:(@testbranch $(args...))))
end

export BranchTestSet, @testbranch

end
