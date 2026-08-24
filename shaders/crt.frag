#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sourceSize;
    float time;
    float effectStrength;
} ubuf;

layout(binding = 1) uniform sampler2D source;

float noise(vec2 pixel, float frame)
{
    vec3 p = fract(vec3(pixel.xyx) * 0.1031);
    p += dot(p, p.yzx + 33.33 + frame);
    return fract((p.x + p.y) * p.z);
}

vec2 curvature(vec2 uv, float amount)
{
    vec2 p = uv * 2.0 - 1.0;
    p.x *= 1.0 + amount * p.y * p.y;
    p.y *= 1.0 + amount * p.x * p.x;
    return p * 0.5 + 0.5;
}

void main()
{
    float strength = clamp(ubuf.effectStrength, 0.0, 1.0);
    vec2 uv = curvature(qt_TexCoord0, 0.055 * strength);
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float edgePixels = edge * min(ubuf.sourceSize.x, ubuf.sourceSize.y);
    vec3 frameSurface = vec3(0.090, 0.094, 0.078);
    vec3 tubeWell = vec3(0.006, 0.007, 0.005);

    // Paint the illustrated bezel outside the warped aperture. Its inner edge
    // therefore uses exactly the same coordinates as the distorted image.
    if (edge <= 0.0) {
        fragColor = vec4(frameSurface, 1.0) * ubuf.qt_Opacity;
        return;
    }

    vec2 texel = 1.0 / max(ubuf.sourceSize, vec2(1.0));
    float split = 0.75 * strength * texel.x;
    vec4 base = texture(source, uv);
    vec3 colour = vec3(
        texture(source, uv + vec2(split, 0.0)).r,
        base.g,
        texture(source, uv - vec2(split, 0.0)).b
    );

    vec3 bloom = (
        texture(source, uv + vec2(texel.x * 1.5, 0.0)).rgb +
        texture(source, uv - vec2(texel.x * 1.5, 0.0)).rgb +
        texture(source, uv + vec2(0.0, texel.y * 1.5)).rgb +
        texture(source, uv - vec2(0.0, texel.y * 1.5)).rgb
    ) * 0.25;
    colour += bloom * (0.14 * strength);

    float scanline = 1.0 - (0.11 * strength) *
        (0.5 + 0.5 * sin(uv.y * ubuf.sourceSize.y * 3.14159265));
    float phosphorMask = 1.0 - (0.025 * strength) *
        (0.5 + 0.5 * sin(uv.x * ubuf.sourceSize.x * 2.09439510));
    colour *= scanline * phosphorMask;

    float vignette = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y) * 16.0;
    vignette = mix(1.0, pow(clamp(vignette, 0.0, 1.0), 0.18), strength);
    colour *= vignette;

    float grain = noise(floor(uv * ubuf.sourceSize), floor(ubuf.time * 18.0));
    colour += (grain - 0.5) * (0.022 * strength);
    colour *= 1.0 + sin(ubuf.time * 7.0) * (0.008 * strength);

    // Frame, tube well, glass lip, and image all share the warped edge.
    float frameOpening = smoothstep(7.0, 15.0, edgePixels);
    float glassOpening = smoothstep(18.0, 30.0, edgePixels);
    float frameRidge = exp(-pow((edgePixels - 10.0) / 3.5, 2.0)) * 0.028;
    float rimHighlight = exp(-pow((edgePixels - 22.0) / 4.5, 2.0)) * 0.035 * strength;
    colour = mix(tubeWell, colour, glassOpening);
    colour = mix(frameSurface, colour, frameOpening);
    colour += frameRidge * vec3(0.42, 0.40, 0.31);
    colour += rimHighlight * vec3(0.75, 0.62, 0.38);

    fragColor = vec4(max(colour, vec3(0.0)), base.a) * ubuf.qt_Opacity;
}
