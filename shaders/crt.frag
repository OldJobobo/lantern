#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 sourceSize;
    float time;
    float effectStrength;
    float rasterOpacity;
    float rasterGain;
    float channelGlitch;
    float channelGlitchSeed;
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
    float rasterStrength = strength * clamp(ubuf.rasterOpacity, 0.0, 1.0);
    // The dial spans from clean glass to an intentionally pronounced CRT.
    // Midrange stays restrained; 100 must be visually unmistakable.
    float rasterLevel = rasterStrength * clamp(ubuf.rasterGain, 0.25, 4.0);
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
    float rasterY = uv.y * ubuf.sourceSize.y;
    float field = floor(ubuf.time * 20.0);

    // Analog line timing never lands on precisely the same horizontal sample.
    // Keep the weave below a quarter pixel so type stays readable while bright
    // edges visibly respond to small changes in analog line timing.
    float lineWeave = (noise(vec2(floor(rasterY), field), field) - 0.5) * 0.42 * rasterLevel;
    vec2 signalUv = clamp(uv + vec2(lineWeave * texel.x, 0.0), texel * 0.5, vec2(1.0) - texel * 0.5);
    float split = 0.75 * rasterLevel * texel.x;

    // Changing the RGB selector briefly knocks the three channels out of lock.
    // Quantized rows make the displacement read as stacked switcher slices,
    // while the low-level split remains analog and continuous between changes.
    float glitch = clamp(ubuf.channelGlitch, 0.0, 1.0);
    float stackRow = floor(uv.y * 22.0);
    float switchFrame = floor(ubuf.time * 38.0) + ubuf.channelGlitchSeed * 97.0;
    float stackNoise = noise(vec2(stackRow, ubuf.channelGlitchSeed * 53.0), switchFrame);
    float stackGate = step(1.0 - glitch * 0.90, stackNoise);
    float stackDirection = step(0.5, noise(vec2(stackRow + 11.0, 4.0), switchFrame)) * 2.0 - 1.0;
    float stackShift = stackGate * stackDirection * (10.0 + 48.0 * stackNoise) * glitch * texel.x;
    float verticalKick = stackGate * (stackNoise - 0.5) * 5.0 * glitch * texel.y;
    float channelKick = glitch * (4.0 + 19.0 * glitch) * texel.x;
    vec2 glitchUv = clamp(signalUv + vec2(stackShift, verticalKick), texel * 0.5, vec2(1.0) - texel * 0.5);
    vec4 base = texture(source, glitchUv);
    vec3 colour = vec3(
        texture(source, clamp(glitchUv + vec2(split + channelKick * (0.65 + stackGate), 0.0), texel * 0.5, vec2(1.0) - texel * 0.5)).r,
        base.g,
        texture(source, clamp(glitchUv - vec2(split + channelKick * (0.55 + stackGate * 1.35), 0.0), texel * 0.5, vec2(1.0) - texel * 0.5)).b
    );

    // A channel switch should momentarily look broken, not merely soft. Coarse
    // noise, bright dropout flecks, and cyan/magenta sync bars make the burst
    // readable even over an almost-black screen before the signal relocks.
    vec2 staticCell = floor(uv * ubuf.sourceSize * vec2(0.42, 0.30));
    float staticNoise = noise(staticCell, switchFrame + stackRow * 0.17);
    float staticGate = step(0.50 - glitch * 0.16, staticNoise) * glitch;
    float dropout = step(0.91 - glitch * 0.12, noise(staticCell + 19.0, switchFrame + 7.0));
    vec3 switchStatic = mix(vec3(0.03), vec3(0.95), staticNoise);
    switchStatic += dropout * vec3(0.65, 0.92, 0.78);
    colour = mix(colour, switchStatic, staticGate * (0.16 + stackGate * 0.24));

    float syncLine = step(0.90, noise(vec2(stackRow, 31.0), switchFrame + 13.0)) * glitch;
    vec3 channelBar = stackDirection > 0.0 ? vec3(0.85, 0.04, 0.72) : vec3(0.02, 0.82, 0.92);
    colour += channelBar * syncLine * (0.12 + 0.22 * glitch);

    vec3 bloom = (
        texture(source, signalUv + vec2(texel.x * 1.5, 0.0)).rgb +
        texture(source, signalUv - vec2(texel.x * 1.5, 0.0)).rgb +
        texture(source, signalUv + vec2(0.0, texel.y * 1.5)).rgb +
        texture(source, signalUv - vec2(0.0, texel.y * 1.5)).rgb
    ) * 0.25;

    // Two-pixel raster lines respond to phosphor energy instead of darkening
    // every part of the picture equally. A tiny phase tremor suggests beam
    // instability without turning the lines into a distracting downward crawl.
    float luminance = dot(colour, vec3(0.2126, 0.7152, 0.0722));
    float scanPhase = rasterY * 3.14159265 + sin(ubuf.time * 2.3) * 0.55;
    float scanGap = pow(0.5 + 0.5 * sin(scanPhase), 1.55);
    float scanDepth = mix(0.200, 0.090, smoothstep(0.05, 0.70, luminance));
    float lineEnergy = 1.0 + sin(ubuf.time * 6.5 + rasterY * 0.032) * 0.16;
    float scanline = 1.0 - scanGap * scanDepth * lineEnergy * rasterLevel;
    float phosphorMask = 1.0 - (0.025 * rasterLevel) *
        (0.5 + 0.5 * sin(signalUv.x * ubuf.sourceSize.x * 2.09439510));
    colour *= scanline * phosphorMask;

    // Bloom is emitted after the raster mask, allowing bright glyphs to bleed
    // softly into the dark gap between lines like light spreading in real glass.
    colour += bloom * (0.14 * rasterLevel);

    // A camera-visible refresh band takes roughly eight seconds to cross the
    // tube. A dim wake behind the bright edge makes its direction readable.
    float rollPosition = fract(ubuf.time * 0.125);
    float rollDistance = abs(fract(uv.y - rollPosition + 0.5) - 0.5);
    float wakeDistance = abs(fract(uv.y - rollPosition + 0.455) - 0.5);
    float refreshBand = exp(-pow(rollDistance / 0.028, 2.0));
    float refreshWake = exp(-pow(wakeDistance / 0.075, 2.0));
    colour *= 1.0 + (refreshBand * 0.120 - refreshWake * 0.022) * rasterLevel;

    float vignette = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y) * 16.0;
    vignette = mix(1.0, pow(clamp(vignette, 0.0, 1.0), 0.18), strength);
    colour *= vignette;

    float grain = noise(floor(uv * ubuf.sourceSize), floor(ubuf.time * 18.0));
    colour += (grain - 0.5) * (0.022 * rasterLevel);
    float powerFlutter = sin(ubuf.time * 17.0) * 0.0100 + sin(ubuf.time * 3.1) * 0.0060;
    colour *= 1.0 + powerFlutter * rasterLevel;

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
