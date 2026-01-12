shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

uniform vec3 scale; // log scale, so actual_scale = exp(scale)
uniform float opacity;
uniform vec3 sh_0; // degree 0 coef

void vertex() {
	// Billboard quad, size based on scale
	vec3 actual_scale = exp(scale);
	float max_scale = max(actual_scale.x, max(actual_scale.y, actual_scale.z));
	VERTEX = vec3(VERTEX.x * max_scale * 3.0, VERTEX.y * max_scale * 3.0, 0.0); // 3 sigma
}

void fragment() {
	vec3 local_pos = VERTEX;
	
	// Actual scale
	vec3 actual_scale = exp(scale);
	
	// Compute Gaussian value
	vec3 scaled_pos = local_pos / actual_scale;
	float dist_sq = dot(scaled_pos, scaled_pos);
	float gauss = exp(-0.5 * dist_sq);
	
	float alpha = opacity * gauss;
	if (alpha < 0.001) discard;
	
	// Color
	vec3 color = sh_0 * 0.282095 + 0.5;
	color = clamp(color, 0.0, 1.0);
	
	ALBEDO = color;
	ALPHA = alpha;
}