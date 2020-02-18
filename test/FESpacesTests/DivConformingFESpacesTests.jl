module DivConformingFESpacesTests

using Gridap.Geometry
using Gridap.ReferenceFEs
using Gridap.FESpaces

domain =(0,1,0,1)
partition = (3,3)
model = CartesianDiscreteModel(domain,partition)
trian = get_triangulation(model)

order = 2

u(x) = x

V = TestFESpace(
  reffe = :RaviartThomas,
  conformity = :Hdiv,
  order = order,
  model = model,
  dirichlet_tags = [1,6])
test_single_field_fe_space(V)

U = TrialFESpace(V,u)

uh = interpolate(U,u)

#using Gridap.Visualization
#
#writevtk(trian,"trian",nsubcells=10,cellfields=["uh"=>uh])

end # module
