
struct FEOperatorFromWeakForm <: FEOperator
  res::Function
  jac::Function
  trial::FESpace
  test::FESpace
  assem::Assembler
end

function FEOperator(
  res::Function,jac::Function,trial::FESpace,test::FESpace,assem::Assembler)
  FEOperatorFromWeakForm(res,jac,trial,test,assem)
end

function FEOperator(res::Function,jac::Function,args...)
  assem = SparseMatrixAssembler(args...)
  trial,test, = args
  FEOperator(res,jac,trial,test,assem)
end

function FEOperator(
  res::Function,trial::FESpace,test::FESpace,assem::Assembler)
  jac(u,du,dv) = jacobian(x->res(x,dv),u)
  FEOperatorFromWeakForm(res,jac,trial,test,assem)
end

function FEOperator(res::Function,args...)
  assem = SparseMatrixAssembler(args...)
  trial,test, = args
  FEOperator(res,trial,test,assem)
end

get_test(op::FEOperatorFromWeakForm) = op.test
get_trial(op::FEOperatorFromWeakForm) = op.trial

function allocate_residual(op::FEOperatorFromWeakForm,uh::FEFunction)
  V = get_test(op)
  v = get_cell_shapefuns(V)
  vecdata = collect_cell_vector(V,op.res(uh,v))
  allocate_vector(op.assem, vecdata)
end

function residual!(b::AbstractVector,op::FEOperatorFromWeakForm,uh::FEFunction)
  V = get_test(op)
  v = get_cell_shapefuns(V)
  vecdata = collect_cell_vector(V,op.res(uh,v))
  assemble_vector!(b,op.assem, vecdata)
  b
end

function allocate_jacobian(op::FEOperatorFromWeakForm,uh::FEFunction)
  U = get_trial(op)
  V = get_test(op)
  du = get_cell_shapefuns_trial(U)
  v = get_cell_shapefuns(V)
  matdata = collect_cell_matrix(U,V,op.jac(uh,du,v))
  allocate_matrix(op.assem, matdata)
end

function jacobian!(A::AbstractMatrix,op::FEOperatorFromWeakForm,uh::FEFunction)
  U = get_trial(op)
  V = get_test(op)
  du = get_cell_shapefuns_trial(U)
  v = get_cell_shapefuns(V)
  matdata = collect_cell_matrix(U,V,op.jac(uh,du,v))
  assemble_matrix!(A,op.assem,matdata)
  A
end

function residual_and_jacobian!(
  b::AbstractVector,A::AbstractMatrix,op::FEOperatorFromWeakForm,uh::FEFunction)
  U = get_trial(op)
  V = get_test(op)
  du = get_cell_shapefuns_trial(U)
  v = get_cell_shapefuns(V)
  data = collect_cell_matrix_and_vector(U,V,op.jac(uh,du,v),op.res(uh,v))
  assemble_matrix_and_vector!(A, b, op.assem, data)
  (b,A)
end

function residual_and_jacobian(op::FEOperatorFromWeakForm,uh::FEFunction)
  U = get_trial(op)
  V = get_test(op)
  du = get_cell_shapefuns_trial(U)
  v = get_cell_shapefuns(V)
  data = collect_cell_matrix_and_vector(U,V,op.jac(uh,du,v),op.res(uh,v))
  A, b = assemble_matrix_and_vector(op.assem, data)
  (b, A)
end
