# Gaussian Splatting Godot Implementation

This project implements support for KHR_gaussian_splatting extension in Godot Engine, using the Compatibility renderer for WebGL2 compatibility.

## Features

- Loads glTF files with KHR_gaussian_splatting extension
- Renders Gaussian splats as billboards with basic Gaussian falloff
- Supports position, scale, rotation, opacity, and spherical harmonics (degree 0)
- Sorts splats by distance for correct blending

## Limitations

- Basic approximation of Gaussian rendering (not full 2D projection)
- No support for higher degree spherical harmonics
- Sorting is done on CPU, may be slow for many splats
- Only ellipse kernel supported

## Usage

1. Open the project in Godot 4.1+
2. Modify main.gd to load your glTF file with Gaussian splats
3. Run the scene

## Files

- `gaussian_splatting_extension.gd`: GLTF extension handler
- `gaussian_splat_node.gd`: Node for rendering splats
- `gaussian_splat.shader`: Shader for rendering
- `main.gd`: Main script to load glTF
- `main.tscn`: Main scene