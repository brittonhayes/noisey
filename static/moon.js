// Procedural hyperrealistic moon renderer
// Uses layered noise, hand-placed maria, craters with 3D shading, and limb darkening

(function () {
    'use strict';

    const canvas = document.getElementById('moon-canvas');
    const ctx = canvas.getContext('2d');
    const S = canvas.width; // 512
    const R = S / 2;
    const CX = R, CY = R;

    // Seeded PRNG for deterministic results
    let seed = 42;
    function rand() {
        seed = (seed * 16807 + 0) % 2147483647;
        return (seed - 1) / 2147483646;
    }

    // ==========================================
    // Simplex-like 2D noise (value noise with smoothing)
    // ==========================================
    const PERM_SIZE = 512;
    const perm = new Uint8Array(PERM_SIZE);
    (function initPerm() {
        seed = 42;
        for (let i = 0; i < 256; i++) perm[i] = i;
        for (let i = 255; i > 0; i--) {
            const j = Math.floor(rand() * (i + 1));
            const t = perm[i]; perm[i] = perm[j]; perm[j] = t;
        }
        for (let i = 0; i < 256; i++) perm[i + 256] = perm[i];
    })();

    function grad2(hash, x, y) {
        const h = hash & 7;
        const u = h < 4 ? x : y;
        const v = h < 4 ? y : x;
        return ((h & 1) ? -u : u) + ((h & 2) ? -v : v);
    }

    function fade(t) { return t * t * t * (t * (t * 6 - 15) + 10); }
    function lerp(a, b, t) { return a + t * (b - a); }

    function noise2d(x, y) {
        const xi = Math.floor(x) & 255;
        const yi = Math.floor(y) & 255;
        const xf = x - Math.floor(x);
        const yf = y - Math.floor(y);
        const u = fade(xf);
        const v = fade(yf);
        const aa = perm[perm[xi] + yi];
        const ab = perm[perm[xi] + yi + 1];
        const ba = perm[perm[xi + 1] + yi];
        const bb = perm[perm[xi + 1] + yi + 1];
        return lerp(
            lerp(grad2(aa, xf, yf), grad2(ba, xf - 1, yf), u),
            lerp(grad2(ab, xf, yf - 1), grad2(bb, xf - 1, yf - 1), u),
            v
        );
    }

    function fbm(x, y, octaves, lacunarity, gain) {
        let sum = 0, amp = 1, freq = 1, maxAmp = 0;
        for (let i = 0; i < octaves; i++) {
            sum += noise2d(x * freq, y * freq) * amp;
            maxAmp += amp;
            amp *= gain;
            freq *= lacunarity;
        }
        return sum / maxAmp;
    }

    // ==========================================
    // Maria (dark basaltic plains) — defined as soft-edged regions
    // ==========================================
    const maria = [
        // {cx, cy, rx, ry, angle, depth} — normalized 0-1 coords
        { cx: 0.34, cy: 0.29, rx: 0.14, ry: 0.12, a: -0.2, d: 0.38 },   // Mare Imbrium
        { cx: 0.54, cy: 0.26, rx: 0.09, ry: 0.08, a: 0.1, d: 0.32 },    // Mare Serenitatis
        { cx: 0.60, cy: 0.38, rx: 0.11, ry: 0.09, a: 0.15, d: 0.34 },   // Mare Tranquillitatis
        { cx: 0.74, cy: 0.30, rx: 0.06, ry: 0.05, a: 0.0, d: 0.30 },    // Mare Crisium
        { cx: 0.69, cy: 0.50, rx: 0.08, ry: 0.10, a: 0.3, d: 0.28 },    // Mare Fecunditatis
        { cx: 0.36, cy: 0.58, rx: 0.11, ry: 0.09, a: -0.1, d: 0.26 },   // Mare Nubium
        { cx: 0.24, cy: 0.41, rx: 0.13, ry: 0.18, a: 0.05, d: 0.30 },   // Oceanus Procellarum
        { cx: 0.25, cy: 0.65, rx: 0.05, ry: 0.045, a: 0.0, d: 0.24 },   // Mare Humorum
        { cx: 0.11, cy: 0.48, rx: 0.03, ry: 0.04, a: 0.0, d: 0.22 },    // Grimaldi
        { cx: 0.44, cy: 0.44, rx: 0.06, ry: 0.05, a: 0.0, d: 0.20 },    // Sinus Medii
        { cx: 0.54, cy: 0.56, rx: 0.07, ry: 0.06, a: 0.2, d: 0.22 },    // Mare Nectaris
    ];

    function mareInfluence(nx, ny) {
        let total = 0;
        for (const m of maria) {
            const cos = Math.cos(m.a), sin = Math.sin(m.a);
            const dx = nx - m.cx, dy = ny - m.cy;
            const rx = (dx * cos + dy * sin) / m.rx;
            const ry = (-dx * sin + dy * cos) / m.ry;
            let dist = Math.sqrt(rx * rx + ry * ry);
            // Add noise to the boundary for organic shapes
            const noiseDist = fbm(nx * 8 + m.cx * 100, ny * 8 + m.cy * 100, 4, 2.0, 0.5);
            dist += noiseDist * 0.3;
            if (dist < 1.0) {
                const falloff = 1.0 - dist;
                const strength = falloff * falloff * (3 - 2 * falloff); // smoothstep
                total = Math.max(total, strength * m.d);
            }
        }
        return total;
    }

    // ==========================================
    // Craters — procedural with 3D shading
    // ==========================================
    const craters = [];
    seed = 77;
    // Major named craters (hand-placed)
    const namedCraters = [
        { cx: 0.44, cy: 0.76, r: 0.025, bright: 1.3 },  // Tycho — bright ray crater
        { cx: 0.31, cy: 0.44, r: 0.028, bright: 0.9 },   // Copernicus
        { cx: 0.21, cy: 0.45, r: 0.015, bright: 0.8 },   // Kepler
        { cx: 0.16, cy: 0.36, r: 0.018, bright: 1.1 },   // Aristarchus — very bright
        { cx: 0.39, cy: 0.18, r: 0.025, bright: 0.6 },   // Plato — dark floor
        { cx: 0.65, cy: 0.21, r: 0.015, bright: 0.7 },   // Small northern
    ];
    for (const nc of namedCraters) craters.push(nc);

    // Random smaller craters
    for (let i = 0; i < 80; i++) {
        const angle = rand() * Math.PI * 2;
        const dist = Math.sqrt(rand()) * 0.45;
        const cx = 0.5 + Math.cos(angle) * dist;
        const cy = 0.5 + Math.sin(angle) * dist;
        const r = 0.003 + rand() * 0.012;
        const bright = 0.5 + rand() * 0.5;
        craters.push({ cx, cy, r, bright });
    }

    // Tiny micro-craters for texture
    for (let i = 0; i < 200; i++) {
        const angle = rand() * Math.PI * 2;
        const dist = Math.sqrt(rand()) * 0.48;
        const cx = 0.5 + Math.cos(angle) * dist;
        const cy = 0.5 + Math.sin(angle) * dist;
        const r = 0.001 + rand() * 0.003;
        const bright = 0.4 + rand() * 0.4;
        craters.push({ cx, cy, r, bright });
    }

    // Light direction (upper-left, as if sunlight)
    const LIGHT_X = -0.6;
    const LIGHT_Y = -0.5;
    const lightLen = Math.sqrt(LIGHT_X * LIGHT_X + LIGHT_Y * LIGHT_Y);
    const LX = LIGHT_X / lightLen;
    const LY = LIGHT_Y / lightLen;

    function craterShading(nx, ny) {
        let totalLight = 0;
        let totalDarken = 0;
        for (const c of craters) {
            const dx = nx - c.cx;
            const dy = ny - c.cy;
            const dist = Math.sqrt(dx * dx + dy * dy);
            const r = c.r;

            if (dist > r * 2.5) continue;

            if (dist < r) {
                // Inside crater
                const nd = dist / r; // 0 at center, 1 at rim
                // Floor is slightly darker
                const floorDark = (1 - nd * nd) * 0.12;
                // Directional shading inside — lit wall vs shadow wall
                const dotLight = (dx * LX + dy * LY) / (dist + 0.001);
                const wallShade = dotLight * nd * 0.15;
                totalDarken += floorDark - wallShade;

                // Bright rim highlight on the lit side
            } else if (dist < r * 1.4) {
                // Rim area
                const rimDist = (dist - r) / (r * 0.4);
                const rimFade = 1 - rimDist;
                const dotLight = (dx * LX + dy * LY) / dist;
                // Bright on the side facing light, dark on shadow side
                const rimBright = dotLight * rimFade * 0.12 * c.bright;
                totalLight += rimBright;
            } else if (dist < r * 2.5 && c.bright > 1.0) {
                // Ejecta rays for bright craters (like Tycho)
                const rayDist = (dist - r * 1.4) / (r * 1.1);
                const rayFade = (1 - rayDist);
                // Radial ray pattern using noise
                const rayAngle = Math.atan2(dy, dx);
                const rayNoise = noise2d(rayAngle * 6 + c.cx * 50, c.cy * 50);
                const ray = Math.max(0, rayNoise) * rayFade * 0.06 * (c.bright - 1.0);
                totalLight += ray;
            }
        }
        return { light: totalLight, dark: totalDarken };
    }

    // ==========================================
    // Render the moon surface to an ImageData buffer
    // ==========================================
    let surfaceData = null;

    function renderSurface() {
        const imgData = ctx.createImageData(S, S);
        const data = imgData.data;

        for (let py = 0; py < S; py++) {
            for (let px = 0; px < S; px++) {
                const nx = px / S;
                const ny = py / S;
                const dx = nx - 0.5;
                const dy = ny - 0.5;
                const dist = Math.sqrt(dx * dx + dy * dy);
                const idx = (py * S + px) * 4;

                if (dist > 0.5) {
                    data[idx] = 0;
                    data[idx + 1] = 0;
                    data[idx + 2] = 0;
                    data[idx + 3] = 0;
                    continue;
                }

                // ---- Base surface brightness ----
                // Multi-octave noise for highland texture
                const tex1 = fbm(nx * 12, ny * 12, 6, 2.1, 0.52);
                const tex2 = fbm(nx * 24 + 100, ny * 24 + 100, 4, 2.0, 0.45);
                const tex3 = fbm(nx * 48 + 200, ny * 48 + 200, 3, 2.0, 0.4);

                let brightness = 0.58 + tex1 * 0.12 + tex2 * 0.06 + tex3 * 0.03;

                // ---- Maria (dark plains) ----
                const mareVal = mareInfluence(nx, ny);
                brightness -= mareVal;

                // Add subtle texture variation within maria
                if (mareVal > 0.05) {
                    const mareTex = fbm(nx * 30 + 50, ny * 30 + 50, 3, 2.0, 0.5);
                    brightness += mareTex * 0.03 * Math.min(1, mareVal * 5);
                }

                // ---- Crater shading ----
                const cShade = craterShading(nx, ny);
                brightness += cShade.light;
                brightness -= cShade.dark;

                // ---- Limb darkening ----
                const limbDist = dist / 0.5;
                const limbDarken = 1.0 - Math.pow(limbDist, 3) * 0.45;
                brightness *= limbDarken;

                // ---- Subtle directional lighting (global) ----
                // Light from upper-right to match phase shadow direction
                const globalLight = 1.0 + (dx * 0.4 - dy * 0.15) * 0.3;
                brightness *= globalLight;

                // ---- Very subtle warm/cool color variation ----
                // Highlands slightly warm, maria slightly cool
                const warmth = mareVal > 0.1 ? -0.008 : 0.005;

                // Clamp
                brightness = Math.max(0, Math.min(1, brightness));

                const v = Math.round(brightness * 255);
                data[idx] = Math.max(0, Math.min(255, v + Math.round(warmth * 255 * 1.5)));
                data[idx + 1] = Math.max(0, Math.min(255, v + Math.round(warmth * 255 * 0.5)));
                data[idx + 2] = Math.max(0, Math.min(255, v - Math.round(warmth * 255)));
                data[idx + 3] = 255;

                // Soft feathered edge — wider fade for seamless blend
                if (dist > 0.48) {
                    const edgeFade = 1.0 - (dist - 0.48) / 0.02;
                    data[idx + 3] = Math.round(Math.max(0, edgeFade * edgeFade) * 255);
                }
            }
        }

        surfaceData = imgData;
    }

    // ==========================================
    // Phase shadow (terminator) — overlaid on the surface
    // ==========================================
    let currentPhase = 0;

    function drawMoon(phase) {
        currentPhase = phase;
        // Draw cached surface
        ctx.clearRect(0, 0, S, S);
        ctx.putImageData(surfaceData, 0, 0);

        // phase: 0 = dark moon, 1 = fully bright
        ctx.save();
        ctx.beginPath();
        ctx.arc(CX, CY, R, 0, Math.PI * 2);
        ctx.closePath();
        ctx.clip();

        // Spherical shading — radial gradient lit from upper-left
        // Always present to give curvature, darkens the limb/lower-right
        const lightOffX = -0.25;
        const lightOffY = -0.2;
        const sphereGrad = ctx.createRadialGradient(
            CX + R * lightOffX, CY + R * lightOffY, R * 0.05,
            CX + R * lightOffX * 0.3, CY + R * lightOffY * 0.3, R * 1.1
        );
        sphereGrad.addColorStop(0, 'rgba(0,0,0,0)');
        sphereGrad.addColorStop(0.5, 'rgba(0,0,0,0.08)');
        sphereGrad.addColorStop(0.75, 'rgba(0,0,0,0.22)');
        sphereGrad.addColorStop(1, 'rgba(0,0,0,0.45)');
        ctx.fillStyle = sphereGrad;
        ctx.fillRect(0, 0, S, S);

        // Volume-based darkening — nearly invisible at 0, fully revealed at 1
        const darkness = (1 - phase) * 0.97;
        if (darkness > 0.01) {
            ctx.fillStyle = `rgba(17,17,17,${darkness.toFixed(3)})`;
            ctx.fillRect(0, 0, S, S);
        }

        ctx.restore();
    }

    // ==========================================
    // Init — render surface once, then draw with phase
    // ==========================================
    renderSurface();
    drawMoon(0.01); // Start near new moon

    // Expose for app.js
    window.drawMoonPhase = drawMoon;
})();
