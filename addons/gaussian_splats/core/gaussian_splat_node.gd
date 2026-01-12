extends Node3D
class_name GaussianSplatNode

@export var kernel: String = "ellipse"
@export var color_space: String = "srgb_rec709_display"
@export var sorting_method: String = "cameraDistance"
@export var projection: String = "perspective"

var positions: PackedVector3Array
var scales: PackedVector3Array
var rotations: Array  # PackedVector4Array for quaternions
var opacities: PackedFloat32Array
var sh_coefficients: Array  # Array of arrays of PackedVector3Array
var splat_instances: Array

func _ready():
	setup_splats()

func setup_splats():
	for i in range(positions.size()):
		var mesh_instance = MeshInstance3D.new()
		var mesh = create_quad_mesh()
		
		var material = ShaderMaterial.new()
		material.shader = preload("res://addons/gaussian_splats/core/gaussian_splat.gdshader")
		material.set_shader_parameter("scale", scales[i])
		material.set_shader_parameter("opacity", opacities[i])
		if sh_coefficients.size() > 0 and sh_coefficients[0].size() > i:
			material.set_shader_parameter("sh_0", sh_coefficients[0][i])
		else:
			material.set_shader_parameter("sh_0", Vector3(1,1,1))
		material.resource_local_to_scene = true
		mesh.surface_set_material(0, material)
		mesh_instance.mesh = mesh
		mesh_instance.position = positions[i]
		mesh_instance.quaternion = rotations[i]
		add_child(mesh_instance)
		splat_instances.append(mesh_instance)

func create_quad_mesh():
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array([
		Vector3(-1, -1, 0),
		Vector3(1, -1, 0),
		Vector3(1, 1, 0),
		Vector3(-1, 1, 0)
	])
	var indices = PackedInt32Array([0, 1, 2, 2, 3, 0])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _process(delta):
	if sorting_method == "cameraDistance":
		sort_by_distance()

func sort_by_distance():
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var camera_pos = camera.global_transform.origin
	var distances = []
	for i in range(splat_instances.size()):
		var dist = positions[i].distance_to(camera_pos)
		distances.append([dist, i])
	distances.sort()
	
	# Reorder children
	for i in range(distances.size()):
		var idx = distances[i][1]
		move_child(splat_instances[idx], i)
