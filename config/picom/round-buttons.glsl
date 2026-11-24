#version 330
// Smooth round buttons for the Openbox theme "Gruvbox-Round".
// Openbox draws 1-bit circles 16 px across; the shader finds them in the titlebar
// by shape and paints smooth ones over them, with a glyph on hover.
in vec2 texcoord;
uniform sampler2D tex;
vec4 default_post_processing(vec4 c);

// Theme geometry (px): button center from the top, spacing between buttons
const int   TOP = 18, STEP = 29;
const float R = 8.0;
// Titlebar backgrounds of all theme variants: soft, medium, hard, intellij (active, inactive)
const vec3  BGS[5] = vec3[5](vec3(50.0, 48.0, 47.0), vec3(40.0, 40.0, 40.0), vec3(29.0, 32.0, 33.0), vec3(43.0, 45.0, 48.0), vec3(30.0, 31.0, 34.0));
// Button colors under the pointer: close, maximize, iconify (gruvbox, then intellij)
const vec3  HOVER[6] = vec3[6](vec3(255.0, 106.0, 86.0), vec3(208.0, 211.0, 64.0), vec3(255.0, 210.0, 90.0),
                               vec3(238.0, 118.0, 118.0), vec3(124.0, 196.0, 130.0), vec3(242.0, 197.0, 92.0));

ivec2 size;
bool flip;

vec3 at(int x, int y) {                 // y counts from the top of the window
    return texelFetch(tex, ivec2(x, flip ? size.y - 1 - y : y), 0).rgb;
}
bool same(vec3 a, vec3 b) { return all(lessThan(abs(a - b) * 255.0, vec3(1.5))); }
float seg(vec2 p, vec2 a, vec2 b) {
    vec2 d = b - a;
    return length(p - a - d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0));
}

bool is_button(int cx, int cy, out vec3 c, out vec3 bg) {
    c = at(cx, cy);
    bg = at(cx - 10, cy);
    bool known = false;
    for (int k = 0; k < 5; k++) known = known || same(bg, BGS[k] / 255.0);
    if (!known) return false;
    if (same(c, bg)) return false;
    return same(at(cx - 8, cy), c) && same(at(cx + 7, cy), c)
        && same(at(cx, cy - 8), c) && same(at(cx, cy + 7), c)
        && same(at(cx - 9, cy), bg) && same(at(cx + 8, cy), bg)
        && same(at(cx, cy - 9), bg) && same(at(cx, cy + 8), bg)
        && same(at(cx - 8, cy - 8), bg) && same(at(cx + 7, cy + 7), bg);
}

vec4 smooth_button(vec2 p, vec4 orig) {
    if (p.y > float(TOP + 12) || p.x < float(size.x) - 100.0 || size.x < 110 || size.y < 40) return orig;
    for (int i = 0; i < 3; i++) {
        for (int off = 19; off <= 20; off++) {     // maximized / normal window
            int cx = size.x - off - i * STEP;
            vec2 d = p - vec2(float(cx), float(TOP));
            if (abs(d.x) > 10.0 || abs(d.y) > 10.0) continue;
            vec3 c, bg;
            if (!is_button(cx, TOP, c, bg)) continue;
            vec3 col = mix(bg, c, clamp(R + 0.5 - length(d), 0.0, 1.0));
            bool hover = false;                    // any hover color: --yellow-button may swap them
            for (int k = 0; k < 6; k++) hover = hover || same(c, HOVER[k] / 255.0);
            if (hover) {
                float g = i == 0 ? min(seg(d, vec2(-3.0, -3.0), vec2(3.0, 3.0)), seg(d, vec2(-3.0, 3.0), vec2(3.0, -3.0)))
                        : i == 1 ? min(seg(d, vec2(-3.6, 0.0), vec2(3.6, 0.0)), seg(d, vec2(0.0, -3.6), vec2(0.0, 3.6)))
                                 : seg(d, vec2(-3.6, 0.0), vec2(3.6, 0.0));
                col = mix(vec3(0.114, 0.125, 0.129), col, clamp(g - 0.35, 0.0, 1.0));
            }
            return vec4(col, orig.a);
        }
    }
    return orig;
}

vec4 window_shader() {
    size = textureSize(tex, 0);
    vec4 c = texelFetch(tex, ivec2(texcoord), 0);
    vec2 p = texcoord;
    flip = false;
    vec4 r = smooth_button(p, c);
    flip = true;                        // in case the texture is flipped
    r = smooth_button(vec2(p.x, float(size.y) - p.y), r);
    return default_post_processing(r);
}
