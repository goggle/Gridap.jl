"""
    const Point{D,T} = VectorValue{D,T}

Type representing a point of D dimensions with coordinates of type T.
Fields are evaluated at vectors of `Point` objects.
"""
const Point{D,T} = VectorValue{D,T}

"""
    abstract type Field <: Map

Abstract type representing a physical (scalar, vector, or tensor) field. The
domain is a `Point` and the range a scalar (i.e., a sub-type of Julia `Number`),
a `VectorValue`, or a `TensorValue`.

These different cases are distinguished by the return value obtained when evaluating them. E.g.,
a physical field returns a vector of values when evaluated at a vector of points, and a basis of `nf` fields
returns a 2d matrix (`np` x `nf`) when evaluated at a vector of `np` points.

The following functions (i.e., the `Map` API) need to be overloaded:

- [`evaluate!(cache,f,x)`](@ref)
- [`return_cache(f,x)`](@ref)

and optionally

- [`return_type(f,x)`](@ref)

A `Field` can also provide its gradient if the following function is implemented
- [`gradient(f)`](@ref)

Higher derivatives can be obtained if the resulting object also implements this method.


The next paragraph is out-of-date:

Moreover, if the [`gradient(f)`](@ref) is not provided, a default implementation that uses the
following functions will be used.

- [`evaluate_gradient!(cache,f,x)`](@ref)
- [`return_gradient_cache(f,x)`](@ref)

Higher order derivatives require the implementation of

- [`evaluate_hessian!(cache,f,x)`](@ref)
- [`return_hessian_cache(f,x)`](@ref)

These four methods are only designed to be called by the default implementation of [`field_gradient(f)`](@ref) and thus
cannot be assumed that they are available for an arbitrary field. For this reason, these functions are not
exported. The general way of evaluating a gradient of a field is to
build the gradient with [`gradient(f)`](@ref) and evaluating the resulting object. For evaluating
the hessian, use two times `gradient`.

The interface can be tested with

- [`test_field`](@ref)

For performance, the user can also consider a _vectorised_ version of the
`Field` API that evaluates the field in a vector of points (instead of only one
point). E.g., the `evaluate!` function for a vector of points returns a vector
of scalar, vector or tensor values.

"""
abstract type Field <: Map end

evaluate!(c,f::Field,x::Point) = @abstractmethod

# Differentiation

function gradient end
const ∇ = gradient
∇∇(f) = gradient(gradient(f))

gradient(f,::Val{1}) = ∇(f)
gradient(f,::Val{2}) = ∇∇(f)


"""
Type that represents the gradient of a field. The wrapped field implements must
implement `evaluate_gradient!` and `return_gradient_cache` for this gradient
to work.

N is how many times the gradient is applied
"""
struct FieldGradient{N,F} <: Field
  object::F
  FieldGradient{N}(object::F) where {N,F} = new{N,F}(object)
end

gradient(f::Field) = FieldGradient{1}(f)
gradient(f::FieldGradient{N}) where N = FieldGradient{N+1}(f.object)

testargs(f::FieldGradient,x::Point) = testargs(f.object,x)
return_value(f::FieldGradient,x::Point) = evaluate(f,testargs(f,x)...)
return_cache(f::FieldGradient,x::Point) = nothing
evaluate!(cache,f::FieldGradient,x::Point) = @abstractmethod

# Default methods for arrays of points

function testargs(f::Field,x::AbstractArray{<:Point})
  y = copy(x)
  broadcast!(xi->first(testargs(f,xi)),y,x)
  (y,)
end

@inline function return_cache(f::Field,x::AbstractArray{<:Point})
  T = return_type(f,testitem(x))
  s = size(x)
  ab = zeros(T,s)
  cb = CachedArray(ab)
  cf = return_cache(f,testitem(x))
  cb, cf
end

@inline function evaluate!(c,f::Field,x::AbstractArray{<:Point})
  cb, cf = c
  sx = size(x)
  setsize!(cb,sx)
  r = cb.array
  for i in eachindex(x)
    @inbounds r[i] = evaluate!(cf,f,x[i])
  end
  r
end

# GenericField

"""
A wrapper for objects that can act as fields, e.g., functions which implement the `Field` API.
"""
struct GenericField{T} <: Field
  object::T
end

#@inline Field(f) = GenericField(f)
@inline GenericField(f::Field) = f

testargs(a::GenericField,x::Point) = testargs(a.object,x)
return_value(a::GenericField,x::Point) = return_value(a.object,x)
return_cache(a::GenericField,x::Point) = return_cache(a.object,x)
@inline evaluate!(cache,a::GenericField,x::Point) = evaluate!(cache,a.object,x)

function return_cache(f::FieldGradient{N,<:GenericField},x::Point) where N
  return_cache(FieldGradient{N}(f.object.object),x)
end

@inline function evaluate!(c,f::FieldGradient{N,<:GenericField},x::Point) where N
  evaluate!(c,FieldGradient{N}(f.object.object),x)
end

# Make Field behave like a collection

@inline Base.length(::Field) = 1
@inline Base.size(::Field) = ()
@inline Base.axes(::Field) = ()
@inline Base.IteratorSize(::Type{<:Field}) = Base.HasShape{0}()
@inline Base.eltype(::Type{T}) where T<:Field = T
@inline Base.iterate(a::Field) = (a,nothing)
@inline Base.iterate(a::Field,::Nothing) = nothing
@inline Base.getindex(a::Field,i::Integer) =  (@check i == 1; a)

# Zero field

@inline Base.zero(a::Field) = ZeroField(a)

"""
It represents `0.0*f` for a field `f`.
"""
struct ZeroField{F} <: Field
  field::F
end

return_cache(z::ZeroField,x::Point) = zero(return_type(z.field,x))
@inline evaluate!(cache,z::ZeroField,x::Point) = cache

function return_cache(z::ZeroField,x::AbstractArray{<:Point})
  E = return_type(z.field,testitem(x))
  c = zeros(E,size(x))
  CachedArray(c)
end

function evaluate!(c,f::ZeroField,x::AbstractArray{<:Point})
  nx = size(x)
  if size(c) != nx
    setsize!(c,nx)
    fill!(c.array,zero(eltype(c)))
  end
  c.array
end

@inline gradient(z::ZeroField) = ZeroField(gradient(z.field))

# Make Number behave like Field
#

# Number itself does not implement the Field interface since Number objects are not callable in Julia.
# Thus, wrapping a Number in a GenericField does not makes sense since the wrapped object
# is assumed to implement the Field interface.
# I think it is conceptually better to have ConstantField as struct otherwise we break the invariant
# "for any object wrapped in a GenericField we can assume that it implements the Field interface"
struct ConstantField{T<:Number} <: Field
  object::T
end

@inline function evaluate!(c,f::ConstantField,x::Point)
  f.object
end

function return_cache(f::ConstantField,x::AbstractArray{<:Point})
  nx = size(x)
  c = fill(f.object,nx)
  CachedArray(c)
end

function evaluate!(c,f::ConstantField,x::AbstractArray{<:Point})
  nx = size(x)
  if size(c) != nx
    setsize!(c,nx)
    fill!(c.array,f.object)
  end
  c.array
end

@inline function return_cache(f::FieldGradient{N,<:ConstantField},x::Point) where N
  gradient(f.object.object,Val(N))(x)
end

@inline evaluate!(c,f::FieldGradient{N,<:ConstantField},x::Point) where N = c

@inline function return_cache(f::FieldGradient{N,<:ConstantField},x::AbstractArray{<:Point}) where N
  CachedArray(gradient(f.object.object,Val(N)).(x))
end

function evaluate!(c,f::FieldGradient{N,<:ConstantField},x::AbstractArray{<:Point}) where N
  nx = size(x)
  if size(c) != nx
    setsize!(c,nx)
    fill!(c.array,zero(eltype(c)))
  end
  c.array
end

## Make Function behave like Field

return_cache(f::FieldGradient{N,<:Function},x::Point) where N = gradient(f.object,Val(N))
@inline evaluate!(c,f::FieldGradient{N,<:Function},x::Point) where N = c(x)

# Operations

"""
A `Field` that is obtained as a given operation over a tuple of fields.
"""
struct OperationField{O,F} <: Field
  op::O
  fields::F
end

function return_value(c::OperationField,x::Point)
  fx = map(f -> return_value(f,x),c.fields)
  return_value(c.op,fx...)
end

function return_cache(c::OperationField,x::Point)
  cl = map(fi -> return_cache(fi,x),c.fields)
  lx = map(fi -> return_value(fi,x),c.fields)
  ck = return_cache(c.op,lx...)
  ck, cl
end

@inline function evaluate!(cache,c::OperationField,x::Point)
  ck, cf = cache
  lx = map((ci,fi) -> evaluate!(ci,fi,x),cf,c.fields)
  evaluate!(ck,c.op,lx...)
end

function return_cache(c::OperationField,x::AbstractArray{<:Point})
  cf = map(fi -> return_cache(fi,x),c.fields)
  lx = map((ci,fi) -> evaluate!(ci,fi,x),cf,c.fields)
  ck = return_cache(c.op,map(testitem,lx)...)
  r = c.op.(lx...)
  ca = CachedArray(r)
  ca, ck, cf
end

@inline function evaluate!(cache,c::OperationField,x::AbstractArray{<:Point})
  ca, ck, cf = cache
  sx = size(x)
  setsize!(ca,sx)
  lx = map((ci,fi) -> evaluate!(ci,fi,x),cf,c.fields)
  r = ca.array
  for i in eachindex(x)
    @inbounds r[i] = evaluate!(ck,c.op,map(lxi -> lxi[i], lx)...)
  end
  r
end

@inline evaluate!(cache,op::Operation,x::Field...) = OperationField(op.op,x)

for op in (:+,:-,:*,:⋅,:inv,:det)
  @eval ($op)(a::Field...) = Operation($op)(a...)
end

# Operation rules e.g.
for op in (:+,:-)
  @eval begin
    function gradient(a::OperationField{typeof($op)})
      f = a.fields
      g = map( gradient, f)
      $op(g...)
    end
  end
end

# Some syntactic sugar
@inline *(A::Number, B::Field) = ConstantField(A)*B
@inline *(A::Field, B::Number) = ConstantField(B)*A
@inline *(A::Function, B::Field) = GenericField(A)*B
@inline *(A::Field, B::Function) = GenericField(B)*A

# Product rules for the gradient

function product_rule(fun,f1,f2,∇f1,∇f2)
  msg = "Product rule not implemented for product $fun between types $(typeof(f1)) and $(typeof(f2))"
  @notimplemented msg
end

function product_rule(::typeof(*),f1::Real,f2::Real,∇f1,∇f2)
  ∇f1*f2 + f1*∇f2
end

function product_rule(::typeof(*),f1::Real,f2::VectorValue,∇f1,∇f2)
  ∇f1⊗f2 + ∇f2*f1
end

function product_rule(::typeof(*),f1::VectorValue,f2::Real,∇f1,∇f2)
  product_rule(*,f2,f1,∇f2,∇f1)
end

function product_rule(::typeof(⋅),f1::VectorValue,f2::VectorValue,∇f1,∇f2)
  ∇f1⋅f2 + ∇f2⋅f1
end

for op in (:*,:⋅,:⊙,:⊗)
  @eval begin
    function gradient(a::OperationField{typeof($op)})
      f = a.fields
      @notimplementedif length(f) != 2
      f1, f2 = f
      g1, g2 = map(gradient, f)
      k(F1,F2,G1,G2) = product_rule($op,F1,F2,G1,G2)
      Operation(k)(f1,f2,g1,g2)
    end
  end
end

# Chain rule
function gradient(f::OperationField{<:Field})
  a = f.op
  @notimplementedif length(f.fields) != 1
  b, = f.fields
  x = ∇(a)∘b
  y = ∇(b)
  y⋅x
end

# Composition

"""
    f∘g

It returns the composition of two fields, which is just `Operation(f)(g)`
"""
@inline Base.:∘(f::Field,g::Field) = Operation(f)(g)

# Other operations

@inline transpose(f::Field) = f

# Testers

"""
    test_field(
      f::Union{Field,AbstractArray{<:Field}},
      x,
      v,
      cmp=(==);
      grad=nothing,
      gradgrad=nothing)

Function used to test the field interface. `v` is an array containing the expected
result of evaluating the field `f` at the point or vector of points `x`. The comparison is performed using
the `cmp` function. For fields objects that support the `gradient` function, the keyword
argument `grad` can be used. It should contain the result of evaluating `gradient(f)` at x.
Idem for `gradgrad`. The checks are performed with the `@test` macro.
"""
function test_field(f::Field, x, v, cmp=(==); grad=nothing, gradgrad=nothing)
  test_mapping(f,(x,),v,cmp)
  if grad != nothing
    test_mapping(∇(f),(x,),grad,cmp)
  end
  if gradgrad != nothing
    test_mapping(∇∇(f),(x,),gradgrad,cmp)
  end
end

