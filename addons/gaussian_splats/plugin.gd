@tool
extends EditorPlugin

var gaussian_extension: GaussianSplattingExtension

func _enter_tree():
	print("Gaussian Splats addon enabled - registering extension")
	gaussian_extension = GaussianSplattingExtension.new()
	GLTFDocument.register_gltf_document_extension(gaussian_extension)

func _exit_tree():
	if gaussian_extension:
		GLTFDocument.unregister_gltf_document_extension(gaussian_extension)
		gaussian_extension = null

# Utility function to load a glTF with Gaussian splats
func load_gaussian_gltf(path: String) -> Node:
	var gltf = GLTFDocument.new()
	var extension = GaussianSplattingExtension.new()
	gltf.register_gltf_document_extension(extension)
	
	var state = GLTFState.new()
	var err = gltf.append_from_file(path, state)
	if err == OK:
		var scene = gltf.generate_scene(state)
		return scene
	else:
		push_error("Failed to load glTF: " + str(err))
		return null
