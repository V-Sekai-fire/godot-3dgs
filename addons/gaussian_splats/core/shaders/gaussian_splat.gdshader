// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lyuma
// Copyright (c) 2026 K. S. Ernest (iFire) Lee

shader_type spatial;
render_mode blend_mix;
render_mode depth_draw_never;
render_mode cull_disabled;
render_mode skip_vertex_transform;
render_mode unshaded;
render_mode fog_disabled;

// FIXME: precision highp float;

uniform vec2 u_focal_length = vec2(2, 2);

// This uniform controls the SH degree at RUNTIME.
// Set from JavaScript to 1, 2, or 3.
uniform int u_sh_degree = 3;

#define SCREEN_QUAD_OUTPUT
//#define SCREEN_QUAD_WIREFRAME
#include "includes/screen_quad_renderer.gdshaderinc"

// All attributes are now always declared. The shader program requires a fixed set of inputs.
// VERTEX_ID & 3 // in vec2 a_quad_vertex;
// VERTEX // in vec3 a_glob_position;
// NORMAL // in vec3 a_glob_scale;
// TANGENT // in vec4 a_glob_rotation;
// COLOR.w // in float a_glob_opacity;

// L=0
// COLOR.rgb // in vec3 a_sh_0;
/*
// L=1
in vec3 a_sh_1;
in vec3 a_sh_2;
in vec3 a_sh_3;
// L=2
in vec3 a_sh_4;
in vec3 a_sh_5;
in vec3 a_sh_6;
in vec3 a_sh_7;
in vec3 a_sh_8;
// L=3
in vec3 a_sh_9;
in vec3 a_sh_10;
in vec3 a_sh_11;
in vec3 a_sh_12;
in vec3 a_sh_13;
in vec3 a_sh_14;
in vec3 a_sh_15;
*/

varying vec3 v_color;
varying float v_opacity;
varying vec3 v_cov2d_inv_upper;
varying vec2 v_center_px;
varying vec2 v_vertex_base;

const float GAUSSIAN_VALUE_CUTOFF = 0.01;

// --- SPHERICAL HARMONICS CONSTANTS ---
const float SH_C0 = 0.28209479177f;
const float SH_C1 = 0.4886025119f;
const float SH_C2_0 = 1.09254843059f;
const float SH_C2_1 = 0.31539156525f;
const float SH_C2_2 = 0.54627421529f;
const float SH_C3_0 = 0.5900435899f;
const float SH_C3_1 = 2.8906114426f;
const float SH_C3_2 = 0.4570457996f;
const float SH_C3_3 = 0.3731763325f;


/*
	arrays[Mesh.ARRAY_TEX_UV] = vec4array_to_vec2_uv_quads(gaussian_data["scales"], gaussian_data["sh_coefficients"][4], 2)
	arrays[Mesh.ARRAY_TEX_UV2] = vec4array_to_vec2_uv_quads(gaussian_data["sh_coefficients"][1], gaussian_data["sh_coefficients"][5], 2)
	arrays[Mesh.ARRAY_CUSTOM0] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][2], gaussian_data["sh_coefficients"][3], gaussian_data["sh_coefficients"][4])
	arrays[Mesh.ARRAY_CUSTOM1] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][6], gaussian_data["sh_coefficients"][7], gaussian_data["sh_coefficients"][5])
	arrays[Mesh.ARRAY_CUSTOM2] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][8], gaussian_data["sh_coefficients"][9], gaussian_data["sh_coefficients"][10])
	arrays[Mesh.ARRAY_WEIGHTS] = vec4array_pairs_2nd_to_half8_custom_quads(gaussian_data["sh_coefficients"][14], gaussian_data["sh_coefficients"][15],
		gaussian_data["sh_coefficients"][10], gaussian_data["sh_coefficients"][13])
	arrays[Mesh.ARRAY_BONES] = vec4array_pairs_to_half8_custom_quads(gaussian_data["sh_coefficients"][11], gaussian_data["sh_coefficients"][12], gaussian_data["sh_coefficients"][13]).to_int32_array()
*/



vec3 GammaToLinearSpace (vec3 sRGB)
{
	// Approximate version from http://chilliant.blogspot.com.au/2012/08/srgb-approximations-for-hlsl.html?m=1
	return sRGB.rgb * (sRGB.rgb * (sRGB.rgb * 0.305306011 + 0.682171111) + 0.012522878);
}

vec3 LinearToGammaSpace(vec3 RGB)
{
  vec3 S1 = sqrt(RGB);
  vec3 S2 = sqrt(S1);
  vec3 S3 = sqrt(S2);
  return 0.662002687 * S1 + 0.684122060 * S2 - 0.323583601 * S3 - 0.0225411470 * RGB;
}

vec3 calculateSphericalHarmonics(vec3 coefficients[16], vec3 v) {
	// L=0 is always calculated.
	vec3 result = SH_C0 * coefficients[0];

	// Use `if` statements based on the uniform to conditionally add higher-order contributions.
	if(u_sh_degree >= 1) {
		float dx = v.x, dy = v.y, dz = v.z;
		result += SH_C1 * dy *  coefficients[1];
		result += SH_C1 * dz * coefficients[2];
		result += SH_C1 * dx * coefficients[3];

		if(u_sh_degree >= 2) {
			float dx2 = dx * dx, dy2 = dy * dy, dz2 = dz * dz;
			result += SH_C2_0 * dx * dy * coefficients[4];
			result += SH_C2_0 * dy * dz * coefficients[5];
			result += SH_C2_1 * (3.0f * dz2 - 1.0f) * coefficients[6];
			result += SH_C2_0 * dx * dz * coefficients[7];
			result += SH_C2_2 * (dx2 - dy2) * coefficients[8];

			if(u_sh_degree >= 3) {
				result += SH_C3_0 * dy * (3.0f * dx2 - dy2) * coefficients[9];
				result += SH_C3_1 * dx * dy * dz * coefficients[10];
				result += SH_C3_2 * dy * (5.0f * dz2 - 1.0f) * coefficients[11];
				result += SH_C3_3 * dz * (5.0f * dz2 - 3.0f) * coefficients[12];
				result += SH_C3_2 * dx * (5.0f * dz2 - 1.0f) * coefficients[13];
				result += SH_C3_1 * dz * (dx2 - dy2) * coefficients[14];
				result += SH_C3_0 * dx * (dx2 - 3.0f * dy2) * coefficients[15];
			}
		}
	}

	result += 0.5;
	result = clamp(result, 0.0, 1.0);

	return result;
}

void vertex() {
	QUAD_VERTEX_BASE = vec2(float(VERTEX_ID & 1), float((VERTEX_ID & 2)>>1));
	QUAD_POS = vec2(0);
    QUAD_SIZE = vec2(100,100);
	QUAD_DIR = vec2(1,0);
	QUAD_DEPTH = 0.5;
	
// VERTEX_ID & 3 // in vec2 a_quad_vertex;
	vec2 a_quad_vertex = vec2(
	float(VERTEX_ID & 1) * 2.0 - 1.0,
	float(VERTEX_ID & 2) * 1.0 - 1.0);
	vec3 a_glob_position = VERTEX;
	vec2 UVy = unpackHalf2x16(floatBitsToUint(UV.y));
	vec2 UV2y = unpackHalf2x16(floatBitsToUint(UV2.y));
	vec2 CUSTOM0y = unpackHalf2x16(floatBitsToUint(CUSTOM0.y));
	vec2 CUSTOM1y = unpackHalf2x16(floatBitsToUint(CUSTOM1.y));
	vec2 CUSTOM2y = unpackHalf2x16(floatBitsToUint(CUSTOM2.y));
	vec2 WEIGHTSy = unpackHalf2x16(floatBitsToUint(BONE_WEIGHTS.y));
	vec2 WEIGHTSw = unpackHalf2x16(floatBitsToUint(BONE_WEIGHTS.w));
	vec2 CUSTOM3y = unpackHalf2x16(floatBitsToUint(CUSTOM3.y));
	vec3 a_glob_scale = vec3(unpackHalf2x16(floatBitsToUint(UV.x)), UVy.x);
	float a_glob_opacity = COLOR.w;
	vec3 a_sh_0 = COLOR.rgb / SH_C0;
	vec3 a_sh_1 = vec3(unpackHalf2x16(floatBitsToUint(UV2.x)), UV2y.x);
	vec3 a_sh_2 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM0.x)), CUSTOM0y.x);
	vec3 a_sh_3 = vec3(CUSTOM0y.y, unpackHalf2x16(floatBitsToUint(CUSTOM0.z)));
	vec3 a_sh_4 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM0.w)), UVy.y);
	vec3 a_sh_5 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM1.w)), UV2y.y);
	vec3 a_sh_6 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM1.x)), CUSTOM1y.x);
	vec3 a_sh_7 = vec3(CUSTOM1y.y, unpackHalf2x16(floatBitsToUint(CUSTOM1.z)));
	vec3 a_sh_8 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM2.x)), CUSTOM2y.x);
	vec3 a_sh_9 = vec3(CUSTOM2y.y, unpackHalf2x16(floatBitsToUint(CUSTOM2.z)));
	vec3 a_sh_10 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM2.w)), WEIGHTSw.x);
	vec3 a_sh_11 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM3.x)), CUSTOM3y.x);
	vec3 a_sh_12 = vec3(CUSTOM3y.y, unpackHalf2x16(floatBitsToUint(CUSTOM3.z)));
	vec3 a_sh_13 = vec3(unpackHalf2x16(floatBitsToUint(CUSTOM3.w)), WEIGHTSw.y);
	vec3 a_sh_14 = vec3(unpackHalf2x16(floatBitsToUint(BONE_WEIGHTS.x)), WEIGHTSy.x);
	vec3 a_sh_15 = vec3(WEIGHTSy.y, unpackHalf2x16(floatBitsToUint(BONE_WEIGHTS.z)));

	vec3 coefficients[16] = vec3[16](a_sh_0, a_sh_1, a_sh_2, a_sh_3, a_sh_4, a_sh_5, a_sh_6, a_sh_7, a_sh_8, a_sh_9, a_sh_10, a_sh_11, a_sh_12, a_sh_13, a_sh_14, a_sh_15);

	// Steps 1-4: Projection, Covariance, and Bounding Box logic (identical)
	vec4 view_space_pos = MODELVIEW_MATRIX * vec4(a_glob_position, 1.0f);

	float z_depth = view_space_pos.z;
	if(z_depth > 0.0) {
		// Cull the whole polygon
		QUAD_DEPTH = -2.0;
	} 
	else {
		vec3 scale = exp(a_glob_scale);

		mat3 rotation_matrix = mat3(TANGENT, BINORMAL, NORMAL);

		mat3 scale_matrix = mat3(vec3(scale.x, 0, 0),
								 vec3(0, scale.y, 0),
								 vec3(0, 0, scale.z));
		//scale_matrix = mat3(1);

	 	mat3 M = rotation_matrix * scale_matrix;
	    mat3 sigma3d = M * transpose(M);
	    mat3 W = transpose(mat3(VIEW_MATRIX));
	    mat3 T = W * sigma3d * transpose(W);
	    mat3 J = mat3(vec3(u_focal_length.x / z_depth, 0, -(u_focal_length.x * view_space_pos.x) / (z_depth * z_depth)), vec3(0, u_focal_length.y / z_depth, -(u_focal_length.y * view_space_pos.y) / (z_depth * z_depth)), vec3(0, 0, 0));
	    mat3 cov2d = transpose(J) * T * J;

	    float det = cov2d[0][0] * cov2d[1][1] - cov2d[0][1] * cov2d[0][1];

		if(det <= 0.0f) { // FIXME
			// Cull the whole polygon
			QUAD_DEPTH = -2.0;
		} else {
			float mid = 0.5f * (cov2d[0][0] + cov2d[1][1]);
			float lambda1 = mid + sqrt(max(0.01f, mid * mid - det));
			float radius = ceil(6.0f * sqrt(max(lambda1, 0.0f)));

			vec4 clip_space_pos = PROJECTION_MATRIX * view_space_pos;
		    vec3 ndc_pos = clip_space_pos.xyz / clip_space_pos.w;
			
			QUAD_POS = (ndc_pos.xy*0.5+0.5) * VIEWPORT_SIZE;
		    QUAD_SIZE = vec2(radius,radius*0.5);
			QUAD_DIR = vec2(1,0);
			QUAD_DEPTH = (CLIP_SPACE_FAR==-1.0) ? ndc_pos.z*0.5+0.5 : ndc_pos.z;


    		// --- STEP 5: Calculate View-Dependent Color using Spherical Harmonics ---
			// TODO: Use EYE_OFFSET to support VR
    		vec3 view_dir = normalize((MODEL_MATRIX * vec4(a_glob_position,1)).xyz - CAMERA_POSITION_WORLD);
			
			vec3 result = calculateSphericalHarmonics(coefficients, view_dir);
			v_color = result;

			v_opacity = a_glob_opacity;

			// --- STEP 6: Pass Data to Fragment Shader ---
			// v_opacity = a_glob_opacity;
			float inv_det = 1.0f / det;
			v_cov2d_inv_upper.x = inv_det * cov2d[1][1];
			v_cov2d_inv_upper.y = -inv_det * cov2d[0][1];
			v_cov2d_inv_upper.z = inv_det * cov2d[0][0];

			//QUAD_DIR = normalize(cov2d[0].xy);
			
			v_center_px = (ndc_pos.xy * 0.5f + 0.5f) * VIEWPORT_SIZE;
		}
	}


	// --- STEP 1: Calculate G(x), the Gaussian Influence ---

	// Find the vector from the current pixel's coordinate (gl_FragCoord.xy)
	// to the center of the projected Gaussian.
	//vec2 d = (FRAGCOORD.xy - v_center_px);
	//d = (SCREEN_UV - v_center_px);

	// Evaluate the quadratic form: (x-μ)ᵀ * (Σ')⁻¹ * (x-μ)
	// This gives us the squared Mahalanobis distance, which is the exponent's power.
	// This value is 0 at the center of the Gaussian and increases as we move away. d.z = sqrt(abs(d.x*d.y))
	//float power = 0.5 * (d.x * d.x * v_cov2d_inv_upper.x + d.y * d.y * v_cov2d_inv_upper.z) + d.x * d.y * v_cov2d_inv_upper.y;
	QUAD_SIZE *= sqrt(abs(v_cov2d_inv_upper.xy)/v_cov2d_inv_upper.z);
	
	UV = a_quad_vertex;
	
	const float power_cutoff = -log(GAUSSIAN_VALUE_CUTOFF);
	const float scale_up = sqrt(power_cutoff);
	
	UV *= scale_up;
	QUAD_SIZE *= scale_up;

	processQuadVertex();
}


// The final view-dependent color, pre-calculated by the vertex shader
// using Spherical Harmonics.
//in vec3 v_color;

// The base opacity of the Gaussian, learned during training.
//in float v_opacity;

// The three unique components of the symmetric 2D inverse covariance matrix (Σ')⁻¹.
// This defines the shape and orientation of the Gaussian's ellipse on the screen.
//in vec3 v_cov2d_inv_upper; // (Σ'⁻¹)[0][0], (Σ'⁻¹)[0][1], (Σ'⁻¹)[1][1]

// The 2D center of the projected Gaussian in screen pixel coordinates.
//in vec2 v_center_px;

// The final color output for the current pixel. This will be sent to the
// GPU's blending unit.
// out vec4 o_frag_color;

void fragment () {
	
	float power = dot(UV, UV);
	
	// The value of the 2D Gaussian function is exp(-power).
	// If the power is large, the influence is negligible. We can discard the pixel
	// early to save computation. A threshold of 4.0 corresponds to e⁻⁴, which is
	// very transparent and visually insignificant.
	const float power_cutoff = -log(GAUSSIAN_VALUE_CUTOFF);
	if (power > power_cutoff) {
		//discard;
	}

	// Calculate the actual influence value of the Gaussian at this pixel.
	float G_influence = exp(-power);


	// --- STEP 2: Calculate the Final Alpha Contribution (aᵢ) ---

	// The final alpha (aᵢ) is the product of the Gaussian's base opacity (α)
	// and its influence at this specific pixel (G(x)).
	float final_alpha = v_opacity * G_influence;

	// Optimization: If the final alpha is practically invisible, discard the pixel.
	// This avoids sending nearly transparent pixels to the blending unit, which can
	// improve performance, especially on mobile or integrated GPUs.r;
	if (OUTPUT_IS_SRGB) {
		if (final_alpha < 1.0 / 255.0) {
			discard; // FIXME
		}
	}

	vec3 final_color = v_color;
	if (OUTPUT_IS_SRGB) {
		final_color = LinearToGammaSpace(final_color);
	}

	ALBEDO = final_color;
	ALPHA = final_alpha;

	processQuadFragment();
}