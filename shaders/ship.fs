#version 330
in vec4 fragColor;
uniform float time;
uniform vec3 tint;
out vec4 finalColor;
void main() {
    float pulse = 0.5 + 0.5 * sin(time * 8.0);
    float scan = 0.5 + 0.5 * sin(gl_FragCoord.y * 0.16 - time * 10.0);
    vec3 base = mix(fragColor.rgb, tint, 0.45);
    vec3 energy = mix(base, vec3(1.0), 0.18 + 0.12 * pulse + 0.10 * scan);
    finalColor = vec4(energy, fragColor.a);
}
