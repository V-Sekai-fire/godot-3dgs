extends GLTFDocumentExtension
class_name GaussianSplattingExtension

const EXTENSION_NAME = "KHR_gaussian_splatting"

var gaussian_meshes_cache = []
var gaussian_data_cache = {}

func _get_supported_extensions():
	print("GaussianSplattingExtension: _get_supported_extensions called")
	return [EXTENSION_NAME]

func _import_preflight(state: GLTFState, extensions_used: PackedStringArray) -> Error:
	print("GaussianSplattingExtension: _import_preflight called")
	if extensions_used.has(EXTENSION_NAME):
		# Initialize class variables
		gaussian_meshes_cache = []
		gaussian_data_cache = {}
		print("GaussianSplattingExtension: Initialized caches")
		
		# Collect meshes with Gaussian primitives
		gaussian_meshes_cache = []
		var meshes = state.json.get("meshes", [])
		for mesh_index in range(meshes.size()):
			var mesh = meshes[mesh_index]
			for primitive in mesh.get("primitives", []):
				if primitive.get("extensions", {}).has(EXTENSION_NAME):
					print("GaussianSplattingExtension: Found Gaussian primitive in mesh ", mesh_index)
					gaussian_meshes_cache.append(mesh_index)
					break
		state.set_additional_data("gaussian_meshes", gaussian_meshes_cache)
	return OK

func _import_node(state: GLTFState, gltf_node: GLTFNode, json: Dictionary, parent_node: Node):
	print("GaussianSplattingExtension: _import_node called for node: ", gltf_node.resource_name)
	if json.has("mesh"):
		var mesh_index = int(json["mesh"])
		print("GaussianSplattingExtension: node has mesh ", mesh_index, " in cache: ", mesh_index in gaussian_meshes_cache)
		if mesh_index in gaussian_meshes_cache:
			if not gaussian_data_cache.has(mesh_index):
				# Extract data for this mesh
				print("GaussianSplattingExtension: Extracting data for mesh ", mesh_index)
				var mesh = state.json["meshes"][mesh_index]
				var positions = PackedVector3Array()
				var scales = PackedVector3Array()
				var rotations = []
				var opacities = PackedFloat32Array()
				var sh_coefficients = []
				var ext_data = null
				for primitive in mesh.get("primitives", []):
					if primitive.get("extensions", {}).has(EXTENSION_NAME):
						ext_data = primitive["extensions"][EXTENSION_NAME]
						var attributes = primitive.get("attributes", {})
						print("GaussianSplattingExtension: attributes: ", attributes.keys())
						
						var position_accessor = attributes.get("POSITION", -1)
						var scale_accessor = attributes.get("KHR_gaussian_splatting:SCALE", -1)
						var rotation_accessor = attributes.get("KHR_gaussian_splatting:ROTATION", -1)
						var opacity_accessor = attributes.get("KHR_gaussian_splatting:OPACITY", -1)
						
						# Spherical harmonics
						var sh_degrees = []
						for deg in range(4):
							var coefs = []
							for n in range(2 * deg + 1):
								var attr = "KHR_gaussian_splatting:SH_DEGREE_%d_COEF_%d" % [deg, n]
								var acc = attributes.get(attr, -1)
								if acc != -1:
									coefs.append(acc)
								else:
									break
							if coefs.size() == 2 * deg + 1:
								sh_degrees.append(coefs)
							else:
								break
						
						# Extract data from accessors
						var positions_part = PackedVector3Array(extract_accessor_data(state, position_accessor, "VEC3"))
						var scales_part = PackedVector3Array(extract_accessor_data(state, scale_accessor, "VEC3"))
						var rotations_data = extract_accessor_data(state, rotation_accessor, "VEC4")
						var rotations_part = []
						for r in rotations_data:
							rotations_part.append(Quaternion(r.x, r.y, r.z, r.w))
						var opacities_part = PackedFloat32Array(extract_accessor_data(state, opacity_accessor, "SCALAR"))
						
						var sh_coefficients_part = []
						for deg_coefs in sh_degrees:
							var deg_data = []
							for acc in deg_coefs:
								deg_data.append(PackedVector3Array(extract_accessor_data(state, acc, "VEC3")))
							sh_coefficients_part.append(deg_data)
						
						positions.append_array(positions_part)
						scales.append_array(scales_part)
						rotations.append_array(rotations_part)
						opacities.append_array(opacities_part)
						if sh_coefficients.is_empty():
							sh_coefficients = sh_coefficients_part
						else:
							for deg in range(sh_coefficients_part.size()):
								if deg < sh_coefficients.size():
									for n in range(sh_coefficients_part[deg].size()):
										if n < sh_coefficients[deg].size():
											sh_coefficients[deg][n].append_array(sh_coefficients_part[deg][n])
				
				var data = {
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
				print("GaussianSplattingExtension: Extracted Gaussian data for mesh ", mesh_index, ": ", positions.size(), " splats")
			
			# Create the GaussianSplatNode
			var data = gaussian_data_cache[mesh_index]
			var gaussian_node = GaussianSplatNode.new()
			gaussian_node.positions = data["positions"]
			gaussian_node.scales = data["scales"]
			gaussian_node.rotations = data["rotations"]
			gaussian_node.opacities = data["opacities"]
			gaussian_node.sh_coefficients = data["sh_coefficients"]
			gaussian_node.kernel = data["kernel"]
			gaussian_node.color_space = data["color_space"]
			gaussian_node.sorting_method = data["sorting_method"]
			gaussian_node.projection = data["projection"]
			print("GaussianSplattingExtension: Created GaussianSplatNode for mesh ", mesh_index)
			return gaussian_node
	
	return OK

func _import_mesh(state: GLTFState, json: Dictionary, extensions: Dictionary, index: int):
	print("GaussianSplattingExtension: _import_mesh called for mesh index: ", index)
	if extensions.has(EXTENSION_NAME):
		var mesh = Mesh.new()
		print("GaussianSplattingExtension: Created placeholder mesh for Gaussian splats")
		return mesh
	return null

func _import_primitive(state: GLTFState, json: Dictionary, extensions: Dictionary, mesh_index: int, primitive_index: int):
	print("GaussianSplattingExtension: _import_primitive called for mesh ", mesh_index, " primitive ", primitive_index, " mode: ", json.get("mode", -1), " extensions: ", extensions.keys())
	if extensions.has(EXTENSION_NAME):
		print("GaussianSplattingExtension: Found Gaussian primitive in mesh ", mesh_index)
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
		
		var data = gaussian_data_cache[mesh_index]
		var ext_data = extensions[EXTENSION_NAME]
		
		# Extract attributes
		var attributes = json.get("attributes", {})
		
		var position_accessor = attributes.get("POSITION", -1)
		var scale_accessor = attributes.get("KHR_gaussian_splatting:SCALE", -1)
		var rotation_accessor = attributes.get("KHR_gaussian_splatting:ROTATION", -1)
		var opacity_accessor = attributes.get("KHR_gaussian_splatting:OPACITY", -1)
		
		# Spherical harmonics
		var sh_degrees = []
		for deg in range(4):
			var coefs = []
			for n in range(2 * deg + 1):
				var attr = "KHR_gaussian_splatting:SH_DEGREE_%d_COEF_%d" % [deg, n]
				var acc = attributes.get(attr, -1)
				if acc != -1:
					coefs.append(acc)
				else:
					break
			if coefs.size() == 2 * deg + 1:
				sh_degrees.append(coefs)
			else:
				break
		
		# Extract data from accessors
		var positions = PackedVector3Array(extract_accessor_data(state, position_accessor, "VEC3"))
		var scales = PackedVector3Array(extract_accessor_data(state, scale_accessor, "VEC3"))
		var rotations_data = extract_accessor_data(state, rotation_accessor, "VEC4")
		var rotations = []
		for r in rotations_data:
			rotations.append(Quaternion(r.x, r.y, r.z, r.w))
		var opacities = PackedFloat32Array(extract_accessor_data(state, opacity_accessor, "SCALAR"))
		
		var sh_coefficients = []
		for deg_coefs in sh_degrees:
			var deg_data = []
			for acc in deg_coefs:
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
			for deg in range(sh_coefficients.size()):
				if deg < data["sh_coefficients"].size():
					for n in range(sh_coefficients[deg].size()):
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
	
	var accessor = state.accessors[accessor_index]
	var buffer_view = state.buffer_views[accessor.buffer_view]
	var buffer = state.buffers[buffer_view.buffer]
	
	var data = buffer
	var offset = buffer_view.byte_offset + accessor.byte_offset
	var count = accessor.count
	var component_type = accessor.component_type
	var component_size = get_component_type_size(component_type)
	var num_components = get_type_components(type)
	var stride = buffer_view.byte_stride if buffer_view.byte_stride > 0 else component_size * num_components
	
	var result = []
	for i in range(count):
		var vec = []
		for c in range(num_components):
			var value = 0
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
