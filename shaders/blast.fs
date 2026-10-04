#version 330
out vec4 finalColor;

uniform vec2  center;     // blast centre in framebuffer pixels (origin bottom-left)
uniform float radius;     // current wave radius
uniform float maxRadius;  // full blast radius
uniform float progress;   // 0 -> 1 over the blast duration
uniform vec3  tint;       // wave colour

void main() {
    float d = distance(gl_FragCoord.xy, center);
    float fade = 1.0 - progress;

    float edge   = 1.0 - smoothstep(0.0, 12.0, abs(d - radius));
    float inner  = (1.0 - smoothstep(0.0, maxRadius, d)) * step(d, radius);
    float ripple = 0.5 + 0.5 * sin(d * 0.35 - progress * 40.0);

    float a = clamp(edge * 1.2 + inner * (0.25 + 0.2 * ripple), 0.0, 1.0) * fade;
    vec3 col = mix(tint, vec3(1.0), edge * 0.6);
    finalColor = vec4(col, a);
}
