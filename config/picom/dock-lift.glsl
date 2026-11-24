#version 330
// Draws Plank a little above the bottom edge of the screen (Plank has no such setting).
// Only the picture moves: the dock's click area already covers the icons in their new place.
in vec2 texcoord;
uniform sampler2D tex;
vec4 default_post_processing(vec4 c);

const int LIFT = 8;      // px

vec4 window_shader() {
    ivec2 p = ivec2(texcoord) + ivec2(0, LIFT);
    if (p.y >= textureSize(tex, 0).y) return vec4(0.0);
    return default_post_processing(texelFetch(tex, p, 0));
}
