#ifndef SCREEN_QUAD_RENDERER
#define SCREEN_QUAD_RENDERER

group_uniforms quad_renderer;
uniform bool draw_quad = true;


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

mat4 QuadTransform2(vec2 pos, vec2 dir, vec2 scale, float z_depth, vec2 screen_size) {
	mat4 modelToScreen = mat4(1);
	
	modelToScreen[3].xy = pos;
	modelToScreen[3].z = z_depth;
	modelToScreen[0].xy = dir * scale.x;
	modelToScreen[1].xy = vec2(-dir.y, dir.x) * scale.y;
	
	return QuadTransform(modelToScreen, screen_size);
}

//#define QuadTransform(screen_transform) __QuadTransform(screen_transform, VIEWPORT_SIZE)
//#define QuadTransform2(pos, dir, scale, screen_size) __QuadTransform2(pos, dir, scale, screen_size, VIEWPORT_SIZE)

#endif /*!SCREEN_QUAD_RENDERER*/