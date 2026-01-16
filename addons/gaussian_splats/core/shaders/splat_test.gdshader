shader_type spatial;

render_mode unshaded;
render_mode cull_disabled;
render_mode skip_vertex_transform;

#define SCREEN_QUAD_OUTPUT
//#define SCREEN_QUAD_WIREFRAME
#include "res://addons/gaussian_splats/core/shaders/includes/screen_quad_renderer.gdshaderinc"
#include "res://addons/gaussian_splats/core/shaders/includes/splat_math.gdshaderinc"

// Ellipse in quadric form to ellipse in parametric form with major and minor axes
// See https://www.shadertoy.com/view/stS3Ww
void extractEllipse(in float a, in float b, in float c, in float d, in float e, in float f, out mat2 axes, out vec2 size, out vec2 center) {
    center = vec2(2.0 * b * d - c * e, 2.0 * a * e - c * d) / (c * c - 4.0 * a * b);
    float g = a * center.x * center.x + b * center.y * center.y + c * center.x * center.y + d * center.x + e * center.y + f;

    float ba = b - a, r = ba / c;
    float ca = 0.5 * sign(c) / sqrt(1.0 + r * r);
    float ch = sqrt(0.5 + ca), sh = sqrt(0.5 - ca) * sign(ba);
    float i = ch - sh, j = ch + sh;

    float ii = i * i, jj = j * j, ij = c * i * j;
    size = sqrt(-2.0 * g / vec2(a * ii + b * jj + ij, a * jj + b * ii - ij));
    axes = mat2(vec2(i, j), vec2(-j, i)) * sqrt(0.5);
}

// Structures
struct Camera {
    vec3 pos;
    mat3 axes;
    float focal;
};

// Ellipsoid projection
void projEllipsoid(in vec3 pos, in mat3 mat, in Camera cam, out mat2 axes, out vec2 size, out vec2 center) {
    mat3 inv = inverse(mat), view = inv * cam.axes, tview = transpose(view);
    vec3 ro = inv * (cam.pos - pos);

    vec3 vo = tview * ro;
    mat3 vv = tview * view * (dot(ro, ro) - 1.0);

    float a = (vo.x * vo.x - vv[0][0]);
    float b = (vo.y * vo.y - vv[1][1]);
    float c = (vo.x * vo.y - vv[0][1]) * 2.0;
    float d = (vo.x * vo.z - vv[0][2]) * cam.focal * 2.0;
    float e = (vo.y * vo.z - vv[1][2]) * cam.focal * 2.0;
    float f = (vo.z * vo.z - vv[2][2]) * cam.focal * cam.focal;

    extractEllipse(a, b, c, d, e, f, axes, size, center);
}

mat4 projectSplatToView(mat4 splatToView){
	Camera cam;
	cam.pos = vec3(0);
	cam.axes = mat3(1);
	cam.focal = 1.0;

	mat4 ellipse_transform = splatToView;
	mat2 axes;
	vec2 size;
	vec2 center;
	projEllipsoid(ellipse_transform[3].xyz, mat3(ellipse_transform), cam, axes, size, center);

	mat4 ellipse_screen_transform = mat4(1);
	ellipse_transform[0].xy = axes[0] * size.x;
	ellipse_transform[1].xy = axes[1] * size.y;
	ellipse_transform[3].xyz = vec3(center,1);

	return ellipse_transform;
}

void vertex() {
	QUAD_VERTEX_BASE = UV;

	QUAD_POS = vec2(VIEWPORT_SIZE/2.0);
	QUAD_DIR = normalize(vec2(1,.2*sin(TIME)));
	QUAD_SIZE = vec2(100, 200);
	QUAD_DEPTH = 0.5;

	mat4 ellipse_transform = MODELVIEW_MATRIX;
	ellipse_transform = projectSplatToView(ellipse_transform);

	vec4 ndc;
	QUAD_POS = (PROJECTION_MATRIX * vec4(ellipse_transform[3].xy, 1, 1)).xy / (PROJECTION_MATRIX * vec4(ellipse_transform[3].xy, 1, 1)).w;
	QUAD_POS = (QUAD_POS * 0.5 + 0.5) * VIEWPORT_SIZE;
	QUAD_DIR = normalize(ellipse_transform[0].xy);
	QUAD_DIR.y *= -1.0;
	QUAD_SIZE.x = length(mat2(PROJECTION_MATRIX) * ellipse_transform[0].xy * VIEWPORT_SIZE * 0.5);
	QUAD_SIZE.y = length(mat2(PROJECTION_MATRIX) * ellipse_transform[1].xy * VIEWPORT_SIZE * 0.5);

	processQuadVertex();
}

void fragment() {
	ALBEDO = vec3(1);
	ALPHA = 1.0;

	ALBEDO = vec3(UV,0);

	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);

	ALPHA = 1.0 - smoothstep(0.0, 1.0, d);

	ALBEDO += clamp(1.0 - abs(d-1.0) / fwidth(d), 0.0, 1.0);
	ALPHA += clamp(1.0 - abs(d-1.0) / fwidth(d), 0.0, 1.0);

	processQuadFragment();

}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
