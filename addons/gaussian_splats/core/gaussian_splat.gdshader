shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, unshaded, fog_disabled;

// FIXME: precision highp float;


uniform vec2 u_focal_length = vec2(2, 2);

// This uniform controls the SH degree at RUNTIME.
// Set from JavaScript to 1, 2, or 3.
uniform int u_sh_degree = 3;

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


void vertex() {



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

	// Steps 1-4: Projection, Covariance, and Bounding Box logic (identical)
	vec4 view_space_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0f);
	
	float z_depth = view_space_pos.z;
	if(z_depth > 0.0) { //z_depth <= 0.1f) { // FIXME
		// Cull the whole polygon
		VERTEX = vec3(2.0f, 2.0f, 2.0f);
		POSITION = vec4(2.0f, 2.0f, 2.0f, 1.0f);
	} else {
		vec3 scale = exp(a_glob_scale);
		
		mat3 rotation_matrix = mat3(TANGENT, BINORMAL, NORMAL);
		/*
		mat3 rotation_matrix = mat3(1.0f - 2.0f * (a_glob_rotation.y * a_glob_rotation.y + a_glob_rotation.z * a_glob_rotation.z), 
									2.0f * (a_glob_rotation.x * a_glob_rotation.y - a_glob_rotation.z * a_glob_rotation.w), 
									2.0f * (a_glob_rotation.x * a_glob_rotation.z + a_glob_rotation.y * a_glob_rotation.w), 
									2.0f * (a_glob_rotation.x * a_glob_rotation.y + a_glob_rotation.z * a_glob_rotation.w), 
									1.0f - 2.0f * (a_glob_rotation.x * a_glob_rotation.x + a_glob_rotation.z * a_glob_rotation.z), 
									2.0f * (a_glob_rotation.y * a_glob_rotation.z - a_glob_rotation.x * a_glob_rotation.w), 
									2.0f * (a_glob_rotation.x * a_glob_rotation.z - a_glob_rotation.y * a_glob_rotation.w), 
									2.0f * (a_glob_rotation.y * a_glob_rotation.z + a_glob_rotation.x * a_glob_rotation.w), 
									1.0f - 2.0f * (a_glob_rotation.x * a_glob_rotation.x + a_glob_rotation.y * a_glob_rotation.y));
		*/
		
		mat3 scale_matrix = mat3(vec3(scale.x, 0, 0),
								 vec3(0, scale.y, 0),
								 vec3(0, 0, scale.z));
		
		mat3 M = rotation_matrix * scale_matrix;
		mat3 sigma3d = M * transpose(M);
		mat3 W = transpose(mat3(VIEW_MATRIX));
		mat3 T = W * sigma3d * transpose(W);
		mat3 J = transpose(mat3(
			vec3(u_focal_length.x / z_depth, 0, -(u_focal_length.x * view_space_pos.x) / (z_depth * z_depth)),
			vec3(0, u_focal_length.y / z_depth, -(u_focal_length.y * view_space_pos.y) / (z_depth * z_depth)),
			vec3(0, 0, 0))); // FIXME: added transpose here
		mat3 cov2d = transpose(J) * T * J;
		
		float det = cov2d[0][0] * cov2d[1][1] - cov2d[0][1] * cov2d[0][1];
		if(det <= 0.0f) { // FIXME
			// Cull the whole polygon
			VERTEX = vec3(2.0f, 2.0f, 2.0f);
			POSITION = vec4(2.0f, 2.0f, 2.0f, 1.0f);
		} else {
		
			float mid = 0.5f * (cov2d[0][0] + cov2d[1][1]);
			float lambda1 = mid + sqrt(max(0.01f, mid * mid - det));
			float radius = ceil(3.0f * sqrt(max(lambda1, 0.0f)));
			
			vec4 clip_space_pos = PROJECTION_MATRIX * view_space_pos;
			// vec4 clip_space_pos = u_projection_matrix * view_space_pos;
			vec2 ndc_pos = clip_space_pos.xy / clip_space_pos.w;
			clip_space_pos.xy += a_quad_vertex * radius / u_focal_length * clip_space_pos.w;
			VERTEX = view_space_pos.xyz + vec3(a_quad_vertex, 0.0);
			POSITION = clip_space_pos;
			//POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);

			// --- STEP 5: Calculate View-Dependent Color using Spherical Harmonics ---
			vec3 view_dir = normalize((MODEL_MATRIX * vec4(a_glob_position, 1.0)).xyz - CAMERA_POSITION_WORLD);

			// L=0 is always calculated.
			vec3 result = SH_C0 * a_sh_0;

			// Use `if` statements based on the uniform to conditionally add higher-order contributions.
			if(u_sh_degree >= 1) {
				float dx = view_dir.x, dy = view_dir.y, dz = view_dir.z;
				result += SH_C1 * dy *  a_sh_1;
				result += SH_C1 * dz * a_sh_2;
				result += SH_C1 * dx * a_sh_3;

				if(u_sh_degree >= 2) {
					float dx2 = dx * dx, dy2 = dy * dy, dz2 = dz * dz;
					result += SH_C2_0 * dx * dy * a_sh_4;
					result += SH_C2_0 * dy * dz * a_sh_5;
					result += SH_C2_1 * (3.0f * dz2 - 1.0f) * a_sh_6;
					result += SH_C2_0 * dx * dz * a_sh_7;
					result += SH_C2_2 * (dx2 - dy2) * a_sh_8;

					if(u_sh_degree >= 3) {
						result += SH_C3_0 * dy * (3.0f * dx2 - dy2) * a_sh_9;
						result += SH_C3_1 * dx * dy * dz * a_sh_10;
						result += SH_C3_2 * dy * (5.0f * dz2 - 1.0f) * a_sh_11;
						result += SH_C3_3 * dz * (5.0f * dz2 - 3.0f) * a_sh_12;
						result += SH_C3_2 * dx * (5.0f * dz2 - 1.0f) * a_sh_13;
						result += SH_C3_1 * dz * (dx2 - dy2) * a_sh_14;
						result += SH_C3_0 * dx * (dx2 - 3.0f * dy2) * a_sh_15;
					}
				}
			}

			v_color = 1.0f / (1.0f + exp(-result));
			v_opacity = a_glob_opacity;

			// --- STEP 6: Pass Data to Fragment Shader ---
			// v_opacity = a_glob_opacity;
			float inv_det = 1.0f / det;
			v_cov2d_inv_upper.x = inv_det * cov2d[1][1];
			v_cov2d_inv_upper.y = -inv_det * cov2d[0][1];
			v_cov2d_inv_upper.z = inv_det * cov2d[0][0];
			// vec2 resolution = vec2(POSITION.w / PROJECTION_MATRIX[0][0] * 2.0f, POSITION.w / PROJECTION_MATRIX[1][1] * 2.0f);
			vec2 resolution = 2.0 * atan(1.0 / vec2(PROJECTION_MATRIX[0].x, PROJECTION_MATRIX[1].y));
			//v_center_px = (ndc_pos * 0.5f + 0.5f) * resolution;
			v_center_px = (ndc_pos - POSITION.xy / POSITION.w) * resolution * resolution;
		}
	}
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

// The base opacity of the Gaussian, learned during training.
//in float v_opacity

	// --- STEP 1: Calculate G(x), the Gaussian Influence ---

	// Find the vector from the current pixel's coordinate (gl_FragCoord.xy)
	// to the center of the projected Gaussian.
	vec2 d = v_center_px; //(FRAGCOORD.xy - v_center_px);

	// Evaluate the quadratic form: (x-μ)ᵀ * (Σ')⁻¹ * (x-μ)
	// This gives us the squared Mahalanobis distance, which is the exponent's power.
	// This value is 0 at the center of the Gaussian and increases as we move away.
	float power = 0.5 * (d.x * d.x * v_cov2d_inv_upper.x + d.y * d.y * v_cov2d_inv_upper.z) + d.x * d.y * v_cov2d_inv_upper.y;
	
	// The value of the 2D Gaussian function is exp(-power).
	// If the power is large, the influence is negligible. We can discard the pixel
	// early to save computation. A threshold of 4.0 corresponds to e⁻⁴, which is
	// very transparent and visually insignificant.
	if (power > 4.0) {
		//discard; // FIXME
	}

	// Calculate the actual influence value of the Gaussian at this pixel.
	float G_x = exp(-power);


	// --- STEP 2: Calculate the Final Alpha Contribution (aᵢ) ---

	// The final alpha (aᵢ) is the product of the Gaussian's base opacity (α)
	// and its influence at this specific pixel (G(x)).
	float final_alpha = v_opacity * G_x;

	// Optimization: If the final alpha is practically invisible, discard the pixel.
	// This avoids sending nearly transparent pixels to the blending unit, which can
	// improve performance, especially on mobile or integrated GPUs.r;
	if (OUTPUT_IS_SRGB) {
		if (final_alpha < 1.0 / 255.0) {
			discard; // FIXME
		}
	}


	// --- STEP 3: Set Final Pixel Color ---

	// Output the final color in "pre-multiplied alpha" format.
	// The RGB color channels are multiplied by the final alpha.
	// The alpha channel is the final alpha itself.
	//
	// Format: vec4(color * alpha, alpha)
	//
	// This format is required for the blending function `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`
	// to correctly calculate the final blended color and transmittance on the GPU.
	vec3 final_color = v_color;
	if (OUTPUT_IS_SRGB) {
		//final_color = GammaToLinearSpace(final_color);
		final_color = LinearToGammaSpace(final_color);
	}
	ALBEDO = final_color;
	ALPHA = final_alpha;
}


// TODO: view-space billboard code
//vec3 right = normalize(vec3(model_view[0][0], model_view[1][0], model_view[2][0]));
//vec3 up = normalize(vec3(model_view[0][1], model_view[1][1], model_view[2][1]));
//vec3 pos = (right * leftright + up * topbottom) * actual_scale;

