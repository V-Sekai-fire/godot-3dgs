#ifndef SCREEN_QUAD_RENDERER
#define SCREEN_QUAD_RENDERER

#ifdef SCREEN_QUAD_WIREFRAME
render_mode wireframe;
#endif /*!SCREEN_QUAD_WIREFRAME*/

group_uniforms quad_renderer;
uniform bool debug_screen_quad = true;

varying vec2 QUAD_VERTEX_BASE;
#define __quad_vertex_base QUAD_VERTEX_BASE

#ifdef SCREEN_QUAD_OUTPUT
varying vec2 QUAD_POS;
varying vec2 QUAD_DIR;
varying vec2 QUAD_SIZE;
varying float QUAD_DEPTH;
#endif /*!SCREEN_QUAD_OUTPUT*/

// Model space to clip space
//mat4 __QuadTransform(vec3 center, vec2 screen_size, vec2 screen_dir, mat4 modelToView){

// Returns screen space to clip space transform
mat4 QuadTransform(mat4 modelToScreen, vec2 screen_size) {
	screen_size /= 2.0;
	
	mat4 screenToClip = modelToScreen;
	
	screenToClip[3].xy -= screen_size;
	screenToClip[3].xy /= screen_size;
	
	screenToClip[0].xy /= screen_size;
	screenToClip[1].xy /= screen_size;
	screenToClip[2].xy /= screen_size;
	
	return screenToClip;
}

// Returns a model space to clip space transform
// z_depth always given in the range [0,1], even for OpenGL.
mat4 QuadTransform2(vec2 pos, vec2 dir, vec2 size, float z_depth, vec2 screen_size) {
	mat4 modelToScreen = mat4(1);
	 
	modelToScreen[3].xy = pos;
	modelToScreen[3].z = mix(CLIP_SPACE_FAR, 1.0, z_depth);
	modelToScreen[0].xy = dir * size.x;
	modelToScreen[1].xy = vec2(-dir.y, dir.x) * size.y;
	
	return QuadTransform(modelToScreen, screen_size);
}

void colorQuad(inout vec3 rgb, inout float alpha){
	
}

void __processQuadVertex(mat4 modelview_matrix, vec2 vertex_base, inout vec4 position){
	position = modelview_matrix * vec4(vertex_base * 2.0 - 1.0, 0, 1);
	position.w = 1.0;
}

float __box(vec2 p, vec2 d){
	p = abs(p) - d;
	return max(p.x, p.y);
}

void __processQuadFragment(inout vec3 albedo, inout float alpha){
#ifdef SCREEN_QUAD_WIREFRAME
	alpha = 1.0;
#else
	if(debug_screen_quad){
		alpha = mix(alpha, 1.0, 0.0);
		float b = __box(__quad_vertex_base - 0.5, vec2(0.5));
		b = (1.0 - clamp(abs(b/fwidth(b) + 0.5), 0.0, 1.0));
		albedo.g += b;
		alpha += b;
	}
#endif /*!SCREEN_QUAD_WIREFRAME*/
}

void __screen_quad_no_op(){}

#ifdef SCREEN_QUAD_OUTPUT
#define __processQuadOutputs MODELVIEW_MATRIX=QuadTransform2(QUAD_POS, QUAD_DIR, QUAD_SIZE, QUAD_DEPTH, VIEWPORT_SIZE)
#else
#define __processQuadOutputs
#endif

#define processQuadVertex __processQuadOutputs; __processQuadVertex(MODELVIEW_MATRIX, __quad_vertex_base.xy, POSITION); __screen_quad_no_op


#define processQuadFragment __processQuadFragment(ALBEDO, ALPHA); __screen_quad_no_op

//#define QuadTransform(screen_transform) __QuadTransform(screen_transform, VIEWPORT_SIZE)
//#define QuadTransform2(pos, dir, scale, screen_size) __QuadTransform2(pos, dir, scale, screen_size, VIEWPORT_SIZE)

#endif /*!SCREEN_QUAD_RENDERER*/