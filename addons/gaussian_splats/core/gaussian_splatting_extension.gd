# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Lyuma
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

extends GLTFDocumentExtension
class_name GaussianSplattingExtension

const EXTENSION_NAME: String = "KHR_gaussian_splatting"

var gaussian_meshes_cache: Array[int] = []
var gaussian_data_cache: Dictionary = {}

## 35mm film format image size. https://en.wikipedia.org/wiki/135_film
const film_format_35mm := Vector2(36,24)

func _get_supported_extensions() -> PackedStringArray:
	print("\n[EXTENSION] _get_supported_extensions called - returning: ", [EXTENSION_NAME])
	return [EXTENSION_NAME]

func _import_pre_generate(state: GLTFState) -> Error:
	
	# make a material
	var material = ShaderMaterial.new()
	material.shader = preload("./shaders/gaussian_splat.gdshader")
	
	var image_resolution : Vector2 = Vector2(1920, 1080)
	var cropped_frame_mm : Vector2 = get_cropped_sensor_size(film_format_35mm, image_resolution)
	var fovy_degrees := 80.0
	var focal_length_px : Vector2 = get_camera_focal_length_px(deg_to_rad(fovy_degrees), image_resolution, cropped_frame_mm)
	
	material.set_shader_parameter("u_focal_length", focal_length_px)
	#print("FOCAL: ", image_resolution, cropped_frame_mm, fovy_degrees, focal_length_px)
	
	material = preload("uid://bonakm4g2gnm4")
	
	for mesh_i in range(len(state.meshes)):
		var gltf_mesh: GLTFMesh = state.meshes[mesh_i]
		var old_import_mesh: ImporterMesh = null
		var import_mesh: ImporterMesh = gltf_mesh.mesh
		if not import_mesh:
			continue
		var primitives_list: Array = state.json["meshes"][mesh_i]["primitives"] as Array
		for prim_i in range(import_mesh.get_surface_count()):
			var gaussian_data: Dictionary = {}
			var json: Dictionary = primitives_list[prim_i] as Dictionary
			if "extensions" in json:
				gaussian_data = extract_gaussian_data(state, json, json["extensions"] as Dictionary, mesh_i, prim_i)
			if gaussian_data.is_empty():
				continue

			print("[GEN_SCENE] Got mesh: ", import_mesh)
			print("[GEN_SCENE] Mesh surface count: ", import_mesh.get_surface_count() if import_mesh else "null")

			print("[GEN_SCENE] Created ShaderMaterial: ", material)
			print("[GEN_SCENE] Material type: ", material.get_class())
			
			if old_import_mesh == null:
				old_import_mesh = import_mesh.duplicate() # ImporterMesh has cheap duplicate
				import_mesh.clear()
			while import_mesh.get_surface_count() < prim_i:
				# Add the intermediate non-gaussian surfaces
				var old_prim_i: int = import_mesh.get_surface_count()
				import_mesh.add_surface(
					old_import_mesh.get_surface_primitive_type(old_prim_i),
					old_import_mesh.get_surface_arrays(old_prim_i),
					[],
					{},
					old_import_mesh.get_surface_material(old_prim_i),
					old_import_mesh.get_surface_name(old_prim_i),
					old_import_mesh.get_surface_format(old_prim_i))
			
			add_gaussian_surface(import_mesh, material, gaussian_data, old_import_mesh.get_surface_name(prim_i))
			print("[GEN_SCENE] ✓ Set ShaderMaterial on mesh surface 0")

		if old_import_mesh == null:
			# No gaussian splats here
			continue
		while import_mesh.get_surface_count() < old_import_mesh.get_surface_count():
			# Add the remaining non-gaussian surfaces
			var old_prim_i: int = import_mesh.get_surface_count()
			import_mesh.add_surface(
				old_import_mesh.get_surface_primitive_type(old_prim_i),
				old_import_mesh.get_surface_arrays(old_prim_i),
				[],
				{},
				old_import_mesh.get_surface_material(old_prim_i),
				old_import_mesh.get_surface_name(old_prim_i),
				old_import_mesh.get_surface_format(old_prim_i))

	return OK


func vec4array_quat_to_vec3_normal_quads(rotations: PackedVector4Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for vec4 in rotations:
		var basis := Basis(Quaternion(vec4.x, vec4.y, vec4.z, vec4.w))
		result.append(basis.z)
		result.append(basis.z)
		result.append(basis.z)
		result.append(basis.z)
	return result

func vec4array_quat_to_float32_tangent_quads(rotations: PackedVector4Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for vec4 in rotations:
		var basis := Basis(Quaternion(vec4.x, vec4.y, vec4.z, vec4.w))
		var d: float = signf(basis.z.dot(basis.z.cross(basis.x)))
		for i in range(4):
			result.append(basis.x.x)
			result.append(basis.x.y)
			result.append(basis.x.z)
			result.append(d)
	return result

func vec4array_to_vec2_uv_quads(array: PackedVector4Array, take_nth_component: PackedVector4Array, comp: int) -> PackedVector2Array:
	var uv_bytes := PackedByteArray()
	uv_bytes.resize(len(array) * 8 * 4)
	var basei: int = 0
	var j: int = 0
	for vec4 in array:
		var extra: float = take_nth_component[j][comp]
		for i in range(basei, basei + 32, 8):
			uv_bytes.encode_half(i, vec4.x)
			uv_bytes.encode_half(i + 2, vec4.y)
			uv_bytes.encode_half(i + 4, vec4.z)
			uv_bytes.encode_half(i + 6, extra)
		basei += 32
		j += 1
	return uv_bytes.to_vector2_array()

func vec4array_pairs_to_half8_custom_quads(array1: PackedVector4Array, array2: PackedVector4Array, take_01th_component: PackedVector4Array) -> PackedByteArray:
	var uv_bytes := PackedByteArray()
	uv_bytes.resize(len(array1) * 16 * 4)
	var basei: int = 0
	for j in range(len(array1)):
		var extra: Vector4 = take_01th_component[j]
		var v1: Vector4 = array1[j]
		var v2: Vector4 = array2[j]
		for i in range(basei, basei + 64, 16):
			uv_bytes.encode_half(i, v1.x)
			uv_bytes.encode_half(i + 2, v1.y)
			uv_bytes.encode_half(i + 4, v1.z)
			uv_bytes.encode_half(i + 6, v2.x)
			uv_bytes.encode_half(i + 8, v2.y)
			uv_bytes.encode_half(i + 10, v2.z)
			uv_bytes.encode_half(i + 12, extra.x)
			uv_bytes.encode_half(i + 14, extra.y)
		basei += 64
	return uv_bytes

func vec4array_pairs_2nd_to_half8_custom_quads(array1: PackedVector4Array, array2: PackedVector4Array, take_2nd_component1: PackedVector4Array, take_2nd_component2: PackedVector4Array) -> PackedByteArray:
	var uv_bytes := PackedByteArray()
	uv_bytes.resize(len(array1) * 16 * 4)
	var basei: int = 0
	for j in range(len(array1)):
		var extra1: Vector4 = take_2nd_component1[j]
		var extra2: Vector4 = take_2nd_component2[j]
		var v1: Vector4 = array1[j]
		var v2: Vector4 = array2[j]
		for i in range(basei, basei + 64, 16):
			uv_bytes.encode_half(i, v1.x)
			uv_bytes.encode_half(i + 2, v1.y)
			uv_bytes.encode_half(i + 4, v1.z)
			uv_bytes.encode_half(i + 6, v2.x)
			uv_bytes.encode_half(i + 8, v2.y)
			uv_bytes.encode_half(i + 10, v2.z)
			uv_bytes.encode_half(i + 12, extra1.z)
			uv_bytes.encode_half(i + 14, extra2.z)
		basei += 64
	return uv_bytes

func add_gaussian_surface(import_mesh: ImporterMesh, material: ShaderMaterial, gaussian_data: Dictionary, name: String):
	var arrays: Array
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = gaussian_data["positions"]
	print("Vertex len " + str((arrays[Mesh.ARRAY_VERTEX])))
	arrays[Mesh.ARRAY_NORMAL] = vec4array_quat_to_vec3_normal_quads(gaussian_data["rotations"])
	print("Normal len " + str((arrays[Mesh.ARRAY_NORMAL])))
	arrays[Mesh.ARRAY_TANGENT] = vec4array_quat_to_float32_tangent_quads(gaussian_data["rotations"])
	print("Tangent len " + str((arrays[Mesh.ARRAY_TANGENT])))
	arrays[Mesh.ARRAY_COLOR] = vec4array_alpha_to_color_array_quads(gaussian_data["sh_coefficients"][0], gaussian_data["opacities"])
	print("Color len " + str((arrays[Mesh.ARRAY_COLOR])))
	arrays[Mesh.ARRAY_TEX_UV] = vec4array_to_vec2_uv_quads(gaussian_data["scales"], gaussian_data["sh_coefficients"][4], 2)
	arrays[Mesh.ARRAY_TEX_UV2] = vec4array_to_vec2_uv_quads(gaussian_data["sh_coefficients"][1], gaussian_data["sh_coefficients"][5], 2)
	arrays[Mesh.ARRAY_CUSTOM0] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][2], gaussian_data["sh_coefficients"][3], gaussian_data["sh_coefficients"][4]).to_float32_array()
	arrays[Mesh.ARRAY_CUSTOM1] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][6], gaussian_data["sh_coefficients"][7], gaussian_data["sh_coefficients"][5]).to_float32_array()
	arrays[Mesh.ARRAY_CUSTOM2] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][8], gaussian_data["sh_coefficients"][9], gaussian_data["sh_coefficients"][10]).to_float32_array()
	arrays[Mesh.ARRAY_CUSTOM3] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][11], gaussian_data["sh_coefficients"][12], gaussian_data["sh_coefficients"][13]).to_float32_array()
	arrays[Mesh.ARRAY_WEIGHTS] = vec4array_pairs_2nd_to_half8_custom_quads(gaussian_data["sh_coefficients"][14], gaussian_data["sh_coefficients"][15],
		gaussian_data["sh_coefficients"][10], gaussian_data["sh_coefficients"][13]).to_float32_array()
	var indices: PackedInt32Array
	indices.resize(len(gaussian_data["positions"]) / 4 * 6)
	# 0 1
	# 2 3
	# 0 1 2 2 1 3
	for i in range(len(gaussian_data["positions"]) / 4):
		indices[i * 6] = i * 4
		indices[i * 6 + 1] = i * 4 + 1
		indices[i * 6 + 2] = i * 4 + 2
		indices[i * 6 + 3] = i * 4 + 2
		indices[i * 6 + 4] = i * 4 + 1
		indices[i * 6 + 5] = i * 4 + 3
	arrays[Mesh.ARRAY_INDEX] = indices
	print("ARRAY_INDEX len " + str((arrays[Mesh.ARRAY_INDEX])))
	# Set material on the mesh surface BEFORE assigning to MeshInstance3D
	import_mesh.add_surface(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		material,
		name,
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) |
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) |
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) |
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT))

func extract_gaussian_data(state: GLTFState, json: Dictionary, extensions: Dictionary, mesh_index: int, primitive_index: int) -> Dictionary:
	if extensions.has(EXTENSION_NAME):
		var data: Dictionary = {
				"positions": PackedVector3Array(),
				"scales": PackedVector4Array(),
				"rotations": PackedVector4Array(),
				"opacities": PackedFloat32Array(),
				"sh_coefficients": [],
				"kernel": "ellipse",
				"color_space": "srgb_rec709_display",
				"sorting_method": "cameraDistance",
				"projection": "perspective"
			}
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
		var positions: PackedVector3Array = vec4array_to_vec3array_quads(extract_accessor_data(state, position_accessor, "VEC3"))
		var scales: PackedVector4Array = extract_accessor_data(state, scale_accessor, "VEC3")
		var rotations_data: PackedVector4Array = extract_accessor_data(state, rotation_accessor, "VEC4")
		#var rotations: Array[Quaternion] = []
		#for r: Variant in rotations_data:
		#	rotations.append(Quaternion(r.x, r.y, r.z, r.w))
		var opacities: PackedVector4Array = extract_accessor_data(state, opacity_accessor, "SCALAR")
		
		var sh_coefficients: Array[PackedVector4Array] = []
		for deg_coefs: Array in sh_degrees:
			for acc: int in deg_coefs:
				sh_coefficients.append(extract_accessor_data(state, acc, "VEC3"))
		# Append to mesh data
		data["positions"] = positions
		data["scales"] = scales
		data["rotations"] = rotations_data
		data["opacities"] = opacities
		# For SH, assume same structure, append
		if data["sh_coefficients"].is_empty():
			data["sh_coefficients"] = sh_coefficients
		#else:
		#	for deg: int in range(sh_coefficients.size()):
		#		if deg < data["sh_coefficients"].size():
		#			for n: int in range(sh_coefficients[deg].size()):
		#				if n < data["sh_coefficients"][deg].size():
		#					data["sh_coefficients"][deg][n].append_array(sh_coefficients[deg][n])
		
		# Update ext_data if not set
		if true: # ext_data["kernel"] == "ellipse":
			data["kernel"] = ext_data.get("kernel", "ellipse")
			data["color_space"] = ext_data.get("colorSpace", "srgb_rec709_display")
			data["sorting_method"] = ext_data.get("sortingMethod", "cameraDistance")
			data["projection"] = ext_data.get("projection", "perspective")
		
		print("GaussianSplattingExtension: Extracted Gaussian data for mesh ", mesh_index, " primitive ", primitive_index, ": ", positions.size(), " splats")
		return data
	return {}

func vec4array_to_vec3array_quads(array: PackedVector4Array) -> PackedVector3Array:
	var result: PackedVector3Array
	for vec in array:
		result.append(Vector3(vec.x, vec.y, vec.z))
		result.append(Vector3(vec.x, vec.y, vec.z))
		result.append(Vector3(vec.x, vec.y, vec.z))
		result.append(Vector3(vec.x, vec.y, vec.z))
	return result

func vec4array_to_colorarray_quads(array: PackedVector4Array) -> PackedColorArray:
	var result: PackedColorArray
	for vec in array:
		result.append(Color(vec.x, vec.y, vec.z, vec.w))
		result.append(Color(vec.x, vec.y, vec.z, vec.w))
		result.append(Color(vec.x, vec.y, vec.z, vec.w))
		result.append(Color(vec.x, vec.y, vec.z, vec.w))
	return result

func vec4array_to_float32array_quads(array: PackedVector4Array) -> PackedFloat32Array:
	var result: PackedFloat32Array
	for vec in array:
		for i in range(4):
			result.append(vec.x)
			result.append(vec.y)
			result.append(vec.z)
			result.append(vec.w)
	return result

func vec4array_alpha_to_color_array_quads(array: PackedVector4Array, opacities: PackedVector4Array) -> PackedColorArray:
	var result: PackedColorArray
	var i: int = 0
	print(array)
	print(opacities)
	print("color alpha len " + str(len(array)) + " colors " + str(len(opacities)))
	for vec in array:
		var alpha: float = clampf(opacities[i].x, 0.0, 1.0)
		vec *= 0.28209479177
		result.append(Color(vec.x, vec.y, vec.z, alpha))
		result.append(Color(vec.x, vec.y, vec.z, alpha))
		result.append(Color(vec.x, vec.y, vec.z, alpha))
		result.append(Color(vec.x, vec.y, vec.z, alpha))
		i += 1
	print("OUTPUT COLORS!!!"  + str(result))
	return result

func extract_accessor_data(state: GLTFState, accessor_index: int, type: String) -> PackedVector4Array:
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

	print(type + "  /  " + str(count) + " / " + str(component_size) + " / " + str(component_type))
	var result: PackedVector4Array
	for i: int in range(count):
		var vec: Vector4
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
			vec[c] = value
		result.append(vec)
	
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

# The physical distance from the focal point to the image in mm.
static func get_camera_focal_length_mm(fovy:float, image_physical_size_mm:Vector2) -> float:
	# Applying SOHCAHTOA to get the ratio between the opposite and adjecent side of the triangle.
	# T=O/A -> A=O/T
	var adjacent_ratio := 0.5 / tan(fovy / 2.0)
	
	# The physical distance from the focal point to the image in mm.
	var focal_length_mm : float = image_physical_size_mm.y * adjacent_ratio
	
	return focal_length_mm

# The physical distance from the focal point to the image in pixels. 
static func get_camera_focal_length_px(fovy:float, image_resolution:Vector2, image_physical_size_mm:Vector2) -> Vector2:
	# The physical distance from the focal point to the image in mm.
	var focal_length_mm : float = get_camera_focal_length_mm(fovy, image_physical_size_mm)
	
	# How many pixels per milimeter on the image.
	# Pixels may be non-square, thus it has split values for x and y. 
	# Aka s_x, s_y
	var px_per_mm : Vector2 = image_resolution / image_physical_size_mm
	
	# The physical distance from the focal point to the image in pixels. 
	# Pixels may be non-square, thus it has split values for x and y. 
	# Aka f_x, f_y
	var focal_length_px : Vector2 = focal_length_mm * px_per_mm
	
	return focal_length_px

static func get_camera_intrinsic_matrix(fovy:float, image_resolution:Vector2, image_physical_size_mm:Vector2, optical_center:=Vector2()) -> Projection:
	var focal_length_px : Vector2 = get_camera_focal_length_px(fovy, image_resolution, image_physical_size_mm)
	
	var projection := Projection()
	
	projection[0].x = focal_length_px.x
	projection[1].y = focal_length_px.y
	projection[2].x = optical_center.x
	projection[2].y = optical_center.y
	
	return projection

# What is the largest image that can fit inside of the film without stretching?
static func get_cropped_sensor_size(film_size:Vector2, image_size:Vector2) -> Vector2:
	var scale : float = 1.0
	
	var ratio : Vector2 = image_size / film_size
	
	if ratio.x > ratio.y:
		# Width is the limiting factor
		scale = film_size.x / image_size.x
	else:
		# Height is the limiting factor
		scale = film_size.y / image_size.y
	
	return image_size * scale
