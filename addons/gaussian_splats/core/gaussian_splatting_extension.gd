extends GLTFDocumentExtension
class_name GaussianSplattingExtension

const EXTENSION_NAME: String = "KHR_gaussian_splatting"

var gaussian_meshes_cache: Array[int] = []
var gaussian_data_cache: Dictionary = {}

func _get_supported_extensions() -> PackedStringArray:
	return [EXTENSION_NAME]

func _import_preflight(state: GLTFState, extensions_used: PackedStringArray) -> Error:
	if extensions_used.has(EXTENSION_NAME):
		# Initialize class variables
		gaussian_meshes_cache = []
		gaussian_data_cache = {}
		
		# Collect meshes with Gaussian primitives
		gaussian_meshes_cache = []
		var meshes: Array = state.json.get("meshes", [])
		for mesh_index: int in range(meshes.size()):
			var mesh: Dictionary = meshes[mesh_index]
			for primitive: Dictionary in mesh.get("primitives", []):
				if primitive.get("extensions", {}).has(EXTENSION_NAME):
					gaussian_meshes_cache.append(mesh_index)
					break
		state.set_additional_data("gaussian_meshes", gaussian_meshes_cache)
	return OK

func _import_node(state: GLTFState, gltf_node: GLTFNode, json: Dictionary, parent_node: Node) -> Error:
	if json.has("mesh"):
		var mesh_index: int = int(json["mesh"])
		if mesh_index in gaussian_meshes_cache:
			if not gaussian_data_cache.has(mesh_index):
				# Extract data for this mesh
				var mesh: Dictionary = state.json["meshes"][mesh_index]
				var positions: PackedVector3Array = PackedVector3Array()
				var scales: PackedVector3Array = PackedVector3Array()
				var rotations: Array[Quaternion] = []
				var opacities: PackedFloat32Array = PackedFloat32Array()
				var sh_coefficients: Array = []
				var ext_data: Variant = null
				for primitive: Dictionary in mesh.get("primitives", []):
					if primitive.get("extensions", {}).has(EXTENSION_NAME):
						ext_data = primitive["extensions"][EXTENSION_NAME]
						var attributes: Dictionary = primitive.get("attributes", {})
						
						var position_accessor: int = attributes.get("POSITION", -1)
						var scale_accessor: int = attributes.get("KHR_gaussian_splatting:SCALE", -1)
						var rotation_accessor: int = attributes.get("KHR_gaussian_splatting:ROTATION", -1)
						var opacity_accessor: int = attributes.get("KHR_gaussian_splatting:OPACITY", -1)
						
						# Spherical harmonics
						var sh_degrees: Array = []
						for deg: int in range(4):
							var coefs: Array[int] = []
							for n: int in range(2 * deg + 1):
								var attr: String = "KHR_gaussian_splatting:SH_DEGREE_%d_COEF_%d" % [deg, n]
								var acc: int = attributes.get(attr, -1)
								if acc != -1:
									coefs.append(acc)
								else:
									break
							if coefs.size() == 2 * deg + 1:
								sh_degrees.append(coefs)
							else:
								break
						
						# Extract data from accessors
						var positions_part: PackedVector3Array = PackedVector3Array(extract_accessor_data(state, position_accessor, "VEC3"))
						var scales_part: PackedVector3Array = PackedVector3Array(extract_accessor_data(state, scale_accessor, "VEC3"))
						var rotations_data: Array = extract_accessor_data(state, rotation_accessor, "VEC4")
						var rotations_part: Array[Quaternion] = []
						for r: Variant in rotations_data:
							rotations_part.append(Quaternion(r.x, r.y, r.z, r.w))
						var opacities_part: PackedFloat32Array = PackedFloat32Array(extract_accessor_data(state, opacity_accessor, "SCALAR"))
						
						var sh_coefficients_part: Array = []
						for deg_coefs: Array in sh_degrees:
							var deg_data: Array[PackedVector3Array] = []
							for acc: int in deg_coefs:
								deg_data.append(PackedVector3Array(extract_accessor_data(state, acc, "VEC3")))
							sh_coefficients_part.append(deg_data)
						
						positions.append_array(positions_part)
						scales.append_array(scales_part)
						rotations.append_array(rotations_part)
						opacities.append_array(opacities_part)
						if sh_coefficients.is_empty():
							sh_coefficients = sh_coefficients_part
						else:
							for deg: int in range(sh_coefficients_part.size()):
								if deg < sh_coefficients.size():
									for n: int in range(sh_coefficients_part[deg].size()):
										if n < sh_coefficients[deg].size():
											sh_coefficients[deg][n].append_array(sh_coefficients_part[deg][n])
				
				var data: Dictionary = {
					"positions": positions,
					"scales": scales,
					"rotations": rotations,
					"opacities": opacities,
					"sh_coefficients": sh_coefficients,
					"kernel": ext_data.get("kernel", "ellipse") if ext_data else "ellipse",
					"color_space": ext_data.get("colorSpace", "srgb_rec709_display") if ext_data else "srgb_rec709_display",
					"sorting_method": ext_data.get("sortingMethod", "cameraDistance") if ext_data else "cameraDistance",
					"projection": ext_data.get("projection", "perspective") if ext_data else "perspective"
				}
				gaussian_data_cache[mesh_index] = data
			
			# Insert individual ImporterMeshInstance3D for each splat into the parent node
			var data: Dictionary = gaussian_data_cache[mesh_index]
			
			for i: int in range(data["positions"].size()):
				var mesh_instance: GLTFNode = GLTFNode.new()
				var quad_mesh: ImporterMesh = create_quad_mesh(data, i)
				var material: ShaderMaterial = ShaderMaterial.new()
				material.shader = preload("res://addons/gaussian_splats/core/gaussian_splat.gdshader")
				material.set_shader_parameter("scale", data["scales"][i])
				material.set_shader_parameter("opacity", data["opacities"][i])
				if data["sh_coefficients"].size() > 0 and data["sh_coefficients"][0].size() > i:
					material.set_shader_parameter("sh_0", data["sh_coefficients"][0][i])
				else:
					material.set_shader_parameter("sh_0", Vector3(1,1,1))
				material.resource_local_to_scene = true
				var gltf_mesh = state.get_meshes()[gltf_node.mesh]
				gltf_mesh.mesh.set_surface_material(gltf_mesh.mesh.get_surface_count() - 1, material)
				var meshes = state.get_meshes()
				meshes[gltf_node.mesh] = gltf_mesh
				# Set transform relative to gltf_node
				var mesh_transform: Transform3D = Transform3D(Basis(gltf_node.rotation).scaled(gltf_node.scale), gltf_node.position)
				var local_transform: Transform3D = Transform3D(Basis(data["rotations"][i]), data["positions"][i])
				mesh_transform = mesh_transform * local_transform
				gltf_node.rotation = mesh_transform.basis.get_rotation_quaternion()
				gltf_node.scale = mesh_transform.basis.get_scale()
				gltf_node.position = mesh_transform.origin
			return OK
	
	return OK

func _import_mesh(state: GLTFState, json: Dictionary, extensions: Dictionary, index: int):
	if extensions.has(EXTENSION_NAME):
		var mesh: Mesh = Mesh.new()
		return mesh
	return null

func _import_primitive(state: GLTFState, json: Dictionary, extensions: Dictionary, mesh_index: int, primitive_index: int):
	if extensions.has(EXTENSION_NAME):
		if not gaussian_data_cache.has(mesh_index):
			gaussian_data_cache[mesh_index] = {
				"positions": PackedVector3Array(),
				"scales": PackedVector3Array(),
				"rotations": [],
				"opacities": PackedFloat32Array(),
				"sh_coefficients": [],
				"kernel": "ellipse",
				"color_space": "srgb_rec709_display",
				"sorting_method": "cameraDistance",
				"projection": "perspective"
			}
		
		var data: Dictionary = gaussian_data_cache[mesh_index]
		var ext_data: Dictionary = extensions[EXTENSION_NAME]
		
		# Extract attributes
		var attributes: Dictionary = json.get("attributes", {})
		
		var position_accessor: int = attributes.get("POSITION", -1)
		var scale_accessor: int = attributes.get("KHR_gaussian_splatting:SCALE", -1)
		var rotation_accessor: int = attributes.get("KHR_gaussian_splatting:ROTATION", -1)
		var opacity_accessor: int = attributes.get("KHR_gaussian_splatting:OPACITY", -1)
		
		# Spherical harmonics
		var sh_degrees: Array = []
		for deg: int in range(4):
			var coefs: Array[int] = []
			for n: int in range(2 * deg + 1):
				var attr: String = "KHR_gaussian_splatting:SH_DEGREE_%d_COEF_%d" % [deg, n]
				var acc: int = attributes.get(attr, -1)
				if acc != -1:
					coefs.append(acc)
				else:
					break
			if coefs.size() == 2 * deg + 1:
				sh_degrees.append(coefs)
			else:
				break
		
		# Extract data from accessors
		var positions: PackedVector3Array = PackedVector3Array(extract_accessor_data(state, position_accessor, "VEC3"))
		var scales: PackedVector3Array = PackedVector3Array(extract_accessor_data(state, scale_accessor, "VEC3"))
		var rotations_data: Array = extract_accessor_data(state, rotation_accessor, "VEC4")
		var rotations: Array[Quaternion] = []
		for r: Variant in rotations_data:
			rotations.append(Quaternion(r.x, r.y, r.z, r.w))
		var opacities: PackedFloat32Array = PackedFloat32Array(extract_accessor_data(state, opacity_accessor, "SCALAR"))
		
		var sh_coefficients: Array = []
		for deg_coefs: Array in sh_degrees:
			var deg_data: Array[PackedVector3Array] = []
			for acc: int in deg_coefs:
				deg_data.append(PackedVector3Array(extract_accessor_data(state, acc, "VEC3")))
			sh_coefficients.append(deg_data)
		
		# Append to mesh data
		data["positions"].append_array(positions)
		data["scales"].append_array(scales)
		data["rotations"].append_array(rotations)
		data["opacities"].append_array(opacities)
		# For SH, assume same structure, append
		if data["sh_coefficients"].is_empty():
			data["sh_coefficients"] = sh_coefficients
		else:
			for deg: int in range(sh_coefficients.size()):
				if deg < data["sh_coefficients"].size():
					for n: int in range(sh_coefficients[deg].size()):
						if n < data["sh_coefficients"][deg].size():
							data["sh_coefficients"][deg][n].append_array(sh_coefficients[deg][n])
		
		# Update ext_data if not set
		if data["kernel"] == "ellipse":
			data["kernel"] = ext_data.get("kernel", "ellipse")
			data["color_space"] = ext_data.get("colorSpace", "srgb_rec709_display")
			data["sorting_method"] = ext_data.get("sortingMethod", "cameraDistance")
			data["projection"] = ext_data.get("projection", "perspective")
		
		print("GaussianSplattingExtension: Extracted Gaussian data for mesh ", mesh_index, " primitive ", primitive_index, ": ", positions.size(), " splats")
	# Return null
	return null

func extract_accessor_data(state: GLTFState, accessor_index: int, type: String) -> Array:
	if accessor_index == -1:
		return []
	
	var accessor: GLTFAccessor = state.accessors[accessor_index]
	var buffer_view: GLTFBufferView = state.buffer_views[accessor.buffer_view]
	var buffer: PackedByteArray = state.buffers[buffer_view.buffer]
	
	var data: PackedByteArray = buffer
	var offset: int = buffer_view.byte_offset + accessor.byte_offset
	var count: int = accessor.count
	var component_type: int = accessor.component_type
	var component_size: int = get_component_type_size(component_type)
	var num_components: int = get_type_components(type)
	var stride: int = buffer_view.byte_stride if buffer_view.byte_stride > 0 else component_size * num_components
	
	var result: Array = []
	for i: int in range(count):
		var vec: Array[float] = []
		for c: int in range(num_components):
			var value: float = 0
			if component_type == 5126:  # FLOAT
				value = data.decode_float(offset + i * stride + c * 4)
			elif component_type == 5121:  # UNSIGNED_BYTE
				value = data[offset + i * stride + c]
				if accessor.normalized:
					value /= 255.0
			elif component_type == 5123:  # UNSIGNED_SHORT
				value = data.decode_u16(offset + i * stride + c * 2)
				if accessor.normalized:
					value /= 65535.0
			elif component_type == 5120:  # SIGNED_BYTE
				value = data.decode_s8(offset + i * stride + c)
				if accessor.normalized:
					value = (value + 128) / 255.0 * 2 - 1
			elif component_type == 5122:  # SIGNED_SHORT
				value = data.decode_s16(offset + i * stride + c * 2)
				if accessor.normalized:
					value = (value + 32768) / 65535.0 * 2 - 1
			vec.append(value)
		
		if type == "SCALAR":
			result.append(vec[0])
		elif type == "VEC3":
			result.append(Vector3(vec[0], vec[1], vec[2]))
		elif type == "VEC4":
			result.append(Quaternion(vec[0], vec[1], vec[2], vec[3]))  # Assuming quaternion
	
	return result

func get_component_type_size(component_type: int) -> int:
	match component_type:
		5120, 5121:  # SIGNED_BYTE, UNSIGNED_BYTE
			return 1
		5122, 5123:  # SIGNED_SHORT, UNSIGNED_SHORT
			return 2
		5126:  # FLOAT
			return 4
		_:
			return 0

func get_type_components(type: String) -> int:
	match type:
		"SCALAR":
			return 1
		"VEC2":
			return 2
		"VEC3":
			return 3
		"VEC4":
			return 4
		_:
			return 0

func create_quad_mesh(data, i) -> ImporterMesh:
	var mesh: ImporterMesh = ImporterMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(-1, -1, 0),
		Vector3(1, -1, 0),
		Vector3(1, 1, 0),
		Vector3(-1, 1, 0)
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 2, 3, 0])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh
