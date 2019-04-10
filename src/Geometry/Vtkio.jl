
function writevtk(grid::Grid,filebase;celldata=Dict(),pointdata=Dict())
  points = vtkpoints(grid)
  cells = vtkcells(grid)
  vtkfile = vtk_grid(filebase, points, cells)
  for (k,v) in celldata
    vtk_cell_data(vtkfile, v, k)
  end
  for (k,v) in pointdata
    vtk_point_data(vtkfile, v, k)
  end
  outfiles = vtk_save(vtkfile)
end

function vtkpoints(grid::Grid{D}) where D
  x = points(grid)
  xflat = collect(x)
  reshape(reinterpret(Float64,xflat),(D,length(x)))
end

# @fverdugo this allocates a lot of small objects
# Not very crucial since it is for visualization
# but it would be nice to have a better way
function vtkcells(grid::Grid)
  types = vtkcelltypedict()
  nodes = vtkcellnodesdict()
  c = celltypes(grid)
  n = cells(grid)
  [  MeshCell(types[ci], ni[nodes[ci]]) for (ci,ni) in zip(c,n) ] 
end

# @fverdugo it would be far more efficient to have
# a Pair instead of a Dict
function vtkcelltypedict()
  d = Dict()
  h = HEX_AXIS
  t = TET_AXIS
  d[()] = VTK_VERTEX
  d[(t,)] = VTK_LINE
  d[(h,)] = VTK_LINE
  d[(t,t)] = VTK_TRIANGLE
  d[(h,h)] = VTK_QUAD
  d[(t,t,t)] = VTK_TETRA
  d[(h,h,h)] = VTK_HEXAHEDRON
  d
end

# @fverdugo it would be far more efficient to have
# a Pair instead of a Dict
function vtkcellnodesdict()
  d = Dict()
  h = HEX_AXIS
  t = TET_AXIS
  d[()] = [1,]
  d[(t,)] = [1,2]
  d[(h,)] = d[(t,)]
  d[(t,t)] = [1,2,3]
  d[(h,h)] = [1,2,4,3]
  d[(t,t,t)] = [1,2,3,4]
  d[(h,h,h)] = [1,2,4,3,5,6,8,7]
  d
end

function writevtk(points::CellPoints,filebase;celldata=Dict(),pointdata=Dict())
  grid, p_to_cell = cellpoints_to_grid(points)
  pdat = prepare_pointdata(pointdata)
  k = "cellid"
  @assert ! haskey(pdat,k)
  pdat[k] = p_to_cell
  writevtk(grid,filebase,pointdata=pdat)
end

function cellpoints_to_grid(points::CellPoints{D}) where D
  ps = Array{Point{D},1}(undef,(0,))
  p_to_cell = Array{Int,1}(undef,(0,))
  for (cell,p) in enumerate(points)
    for pj in p
      push!(ps,pj)
      push!(p_to_cell,cell)
    end
  end
  cs = [ [i,] for i in 1:length(ps) ]
  ts = [ () for i in 1:length(ps) ]
  grid = FlexibleUnstructuredGrid(ps,cs,ts)
  (grid, p_to_cell)
end

function prepare_pointdata(pointdata)
  pdat = Dict()
  for (k,v) in pointdata
    if isa(v,CellArray)
      pdat[k] = collect(flatten(v))
    else
      pdat[k] = v
    end
  end
  pdat
end
