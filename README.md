# Gaussian Splatting Godot Implementation

This project implements initial support for KHR_gaussian_splatting extension in Godot Engine.

https://github.com/KhronosGroup/glTF/pull/2490

 - [x] Successfully packed degree 3 Spherical Harmonics into the Godot Engine vertex attributes
 - [ ] Debugging color reproduction
 - [x] Hard coded focal length calculation
 - [ ] Missing sorting splats by distance for correct blending

## Features

- Loads glTF files with KHR_gaussian_splatting extension
- Renders Gaussian splats as billboards with basic Gaussian falloff
- Supports position, scale, rotation, opacity, and spherical harmonics (degree 3)

## Usage

1. Open the project in Godot 4.6+
2. Import your glTF file with Gaussian splats
3. Run the scene
