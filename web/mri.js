/*
 * MRI report sheet for rps_prompt_exstras (modules/mri).
 *
 * The three scans are rendered on <canvas> to look like real STIR MRI
 * (fat-suppressed T2 — the standard trauma sequence):
 *   - fat dark, muscle mid-grey with texture, bone cortex black, marrow dark,
 *     fluid bright (CSF, discs, joints, bladder) and INJURY OEDEMA BRIGHT
 *   - soft tissue edges, coil intensity falloff, phase-encode ghost and
 *     Rician noise added per pixel like an actual magnitude image
 *
 *   v1  whole body, coronal          — where the injury is
 *   v2  injured region, coronal detail — arrow + note on what is wrong
 *   v3  injured region, axial slice    — cross-section with the lesion
 *
 * Radiological convention: the patient's RIGHT is on the viewer's LEFT.
 */

const CW = 880;   // canvas resolution (square)
const root = document.getElementById('mri');
const sheet = document.getElementById('sheet');

// Lesion anchor per region on the 200×400 coronal body (viewer coords)
const ANCHORS = {
    head: [100, 34], torso: [114, 128], abdomen: [96, 190],
    rarm: [45, 168], larm: [155, 168], rleg: [83, 296], lleg: [117, 296],
};
// coronal detail window per region (square, body units)
const DETAIL_SIZE = { head: 80, torso: 110, abdomen: 110, rarm: 86, larm: 86, rleg: 96, lleg: 96 };

const NOTES = {
    gunshot:   ['Metallic fragment with surrounding oedema', 'Blooming artefact from retained fragment'],
    melee:     ['Intramuscular oedema and haematoma', 'High STIR signal in muscle'],
    fall:      ['Fracture line with bone marrow oedema', 'Cortical break'],
    vehicle:   ['Compression fracture with marrow oedema', 'Cortical disruption with oedema'],
    explosion: ['Multiple retained blast fragments', 'Scattered fragments with oedema'],
    fire:      ['Subcutaneous oedema (thermal injury)', 'Skin and subcutaneous thickening'],
    unknown:   ['Abnormal high signal', 'Signal abnormality'],
};

const REGION_NAMES = {
    head: 'BRAIN', torso: 'CHEST', abdomen: 'ABDOMEN',
    rarm: 'RIGHT ARM', larm: 'LEFT ARM', rleg: 'RIGHT LEG', lleg: 'LEFT LEG',
};

// ─── small helpers ───────────────────────────────────────────────────────────
function rng(seedText) {
    let h = 2166136261;
    for (const c of String(seedText)) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
    return () => {
        h = Math.imul(h ^ (h >>> 15), 2246822507);
        h = Math.imul(h ^ (h >>> 13), 3266489909);
        return ((h ^= h >>> 16) >>> 0) / 4294967296;
    };
}
const gray = (v, a = 1) => `rgba(${v | 0},${v | 0},${v | 0},${a})`;

// tissue texture (blurred noise), built once
const TEXTURE = (() => {
    const n = document.createElement('canvas');
    n.width = n.height = 192;
    const g = n.getContext('2d');
    const img = g.createImageData(192, 192);
    const r = rng('texture');
    for (let i = 0; i < img.data.length; i += 4) {
        const v = 128 + (r() - 0.5) * 150;
        img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
        img.data[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    const out = document.createElement('canvas');
    out.width = out.height = 192;
    const o = out.getContext('2d');
    o.filter = 'blur(1.4px)';
    o.drawImage(n, 0, 0);
    o.drawImage(n, -192, 0); o.drawImage(n, 192, 0); o.drawImage(n, 0, -192); o.drawImage(n, 0, 192);
    return out;
})();

// View = canvas context mapped from "units" (body coordinates) to pixels.
function view(canvas, x0, y0, w) {
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const s = CW / w;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.filter = 'none';
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, CW, CW);
    ctx.setTransform(s, 0, 0, s, -x0 * s, -y0 * s);
    return { ctx, s, x0, y0, w, toPx: (x, y) => [(x - x0) * s, (y - y0) * s] };
}

// draw `fn` blurred by `units` (blur is in canvas pixels, so convert)
function soft(v, units, fn) {
    const { ctx } = v;
    ctx.save();
    ctx.filter = `blur(${Math.max(0.1, units * v.s).toFixed(2)}px)`;
    fn(ctx);
    ctx.restore();
}

function ellipse(ctx, x, y, rx, ry, color, rot = 0) {
    ctx.beginPath();
    ctx.ellipse(x, y, Math.max(rx, 0.01), Math.max(ry, 0.01), rot, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
}
function strokePath(ctx, d, color, width) {
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.stroke(new Path2D(d));
}

function texture(v, alpha, mode = 'overlay') {
    const { ctx } = v;
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = mode;
    ctx.globalAlpha = alpha;
    ctx.fillStyle = ctx.createPattern(TEXTURE, 'repeat');
    ctx.fillRect(0, 0, CW, CW);
    ctx.restore();
}

// ─── coronal anatomy (STIR) ──────────────────────────────────────────────────
const TORSO = new Path2D('M62,80 Q100,70 138,80 Q150,86 148,104 Q146,150 140,200 Q138,226 132,240 L68,240 Q62,226 60,200 Q54,150 52,104 Q50,86 62,80 Z');
const LIMBS = [
    ['M58,86 Q46,110 45,160 Q42,200 36,236', 16],
    ['M142,86 Q154,110 155,160 Q158,200 164,236', 16],
    ['M84,232 Q82,280 82,318 Q80,350 79,390', 24],
    ['M116,232 Q118,280 118,318 Q120,350 121,390', 24],
];

function silhouette(ctx, inset, color) {
    ctx.fillStyle = color;
    ellipse(ctx, 100, 38, 23 - inset, 29 - inset, color);
    ctx.fillRect(91 + inset, 60, 18 - inset * 2, 24);
    ctx.save();
    ctx.translate(100, 160);
    ctx.scale(1 - inset / 48, 1 - inset / 84);
    ctx.translate(-100, -160);
    ctx.fillStyle = color;
    ctx.fill(TORSO);
    ctx.restore();
    for (const [d, w] of LIMBS) strokePath(ctx, d, color, Math.max(w - inset * 2, 1));
}

function drawCoronal(v, rand) {
    // skin / fat (suppressed = dark) / muscle
    soft(v, 0.5, ctx => silhouette(ctx, 0, gray(132)));
    soft(v, 0.6, ctx => silhouette(ctx, 0.9, gray(30)));
    soft(v, 0.9, ctx => silhouette(ctx, 2.6, gray(92)));

    // muscle fascia lines in the limbs
    soft(v, 0.4, ctx => {
        for (const [d, w] of LIMBS) {
            for (const off of [-0.22, 0.22]) {
                ctx.save();
                ctx.translate(off * w, 0);
                strokePath(ctx, d, gray(58), 0.5);
                ctx.restore();
            }
        }
    });

    // ── head: scalp, skull, CSF, grey/white matter, sulci, ventricles
    soft(v, 0.5, ctx => {
        ellipse(ctx, 100, 38, 21.6, 27.6, gray(8));       // outer table
        ellipse(ctx, 100, 38, 20.6, 26.6, gray(34));      // diploe (suppressed marrow)
        ellipse(ctx, 100, 38, 19.6, 25.6, gray(6));       // inner table
        ellipse(ctx, 100, 38, 18.8, 24.8, gray(176));     // CSF
        ellipse(ctx, 100, 39, 17.6, 23.4, gray(118));     // grey matter (brighter than WM on STIR)
    });
    soft(v, 1.4, ctx => {
        ellipse(ctx, 93, 38, 7.5, 13, gray(74));
        ellipse(ctx, 107, 38, 7.5, 13, gray(74));
    });
    soft(v, 0.35, ctx => {
        strokePath(ctx, 'M100,15 L100,62', gray(190), 0.7);                       // falx / fissure
        for (let i = 0; i < 14; i++) {
            const a = rand() * Math.PI * 2;
            const x = 100 + Math.cos(a) * (12 + rand() * 4), y = 39 + Math.sin(a) * (16 + rand() * 5);
            strokePath(ctx, `M${x},${y} q${(rand() - 0.5) * 6},${(rand() - 0.5) * 6} ${(rand() - 0.5) * 7},${(rand() - 0.5) * 7}`, gray(170), 0.55);
        }
        strokePath(ctx, 'M97,34 Q93,40 92,46 M103,34 Q107,40 108,46', gray(200), 1.4);  // lateral ventricles
    });

    // ── neck: cervical spine
    soft(v, 0.4, ctx => {
        for (let y = 64; y < 82; y += 4.5) {
            ellipse(ctx, 100, y + 1.6, 3.4, 1.7, gray(40));
            ellipse(ctx, 100, y + 3.6, 3.2, 0.5, gray(140));
        }
    });

    // ── chest
    soft(v, 1.4, ctx => {
        ellipse(ctx, 79, 124, 16, 33, gray(6));   // lungs: no signal
        ellipse(ctx, 121, 124, 16, 33, gray(6));
    });
    soft(v, 0.5, ctx => {
        for (let i = 0; i < 18; i++) {             // pulmonary vessels
            const side = i % 2 ? 1 : -1;
            const x = 100 + side * (10 + rand() * 18), y = 104 + rand() * 46;
            strokePath(ctx, `M${100 + side * 8},${118} Q${x - side * 4},${y - 6} ${x},${y}`, gray(36), 0.5);
        }
    });
    soft(v, 0.9, ctx => {
        ellipse(ctx, 106, 142, 13, 15, gray(82));   // heart (myocardium)
        ellipse(ctx, 103, 140, 6, 8, gray(20));     // blood pool: flow void
        ellipse(ctx, 111, 146, 5, 6, gray(24));
        ellipse(ctx, 97, 112, 4, 7, gray(14));      // aortic arch flow void
    });
    soft(v, 0.6, ctx => {
        for (let i = 0; i < 7; i++) {               // ribs
            const y = 94 + i * 11;
            strokePath(ctx, `M93,${y} Q70,${y + 2} 60,${y + 16}`, gray(26), 1.5);
            strokePath(ctx, `M107,${y} Q130,${y + 2} 140,${y + 16}`, gray(26), 1.5);
        }
    });

    // ── abdomen
    soft(v, 1.1, ctx => {
        ellipse(ctx, 83, 176, 22, 13, gray(62));       // liver
        ellipse(ctx, 76, 180, 4, 3, gray(170));        // gallbladder (fluid)
        ellipse(ctx, 123, 170, 9, 8, gray(112));       // spleen
        ellipse(ctx, 82, 199, 6.5, 10, gray(122));     // kidneys
        ellipse(ctx, 118, 199, 6.5, 10, gray(122));
        ellipse(ctx, 84, 199, 2, 4, gray(186));
        ellipse(ctx, 116, 199, 2, 4, gray(186));
    });
    soft(v, 0.8, ctx => {
        for (let i = 0; i < 14; i++) {                 // bowel loops
            const x = 86 + rand() * 28, y = 200 + rand() * 24;
            ellipse(ctx, x, y, 3 + rand() * 3, 2.5 + rand() * 2.5, gray(54 + rand() * 50));
            ellipse(ctx, x, y, 1, 1, gray(150 + rand() * 50));
        }
        ellipse(ctx, 100, 229, 9, 6.5, gray(214));     // bladder (fluid = bright)
    });

    // ── spine: dark vertebral bodies, bright hydrated discs, CSF
    soft(v, 0.45, ctx => {
        for (let y = 86; y < 236; y += 8.6) {
            ctx.fillStyle = gray(10);
            ctx.fillRect(95.4, y, 9.2, 7.2);
            ctx.fillStyle = gray(44);
            ctx.fillRect(96.2, y + 0.6, 7.6, 6);
            ctx.fillStyle = gray(150);
            ctx.fillRect(96, y + 7.4, 8, 1);
        }
    });

    // ── pelvis + hips
    soft(v, 0.6, ctx => {
        const ilium = new Path2D('M68,214 Q70,232 90,240 L96,236 Q84,226 80,212 Z M132,214 Q130,232 110,240 L104,236 Q116,226 120,212 Z');
        ctx.fillStyle = gray(42); ctx.fill(ilium);
        ctx.strokeStyle = gray(8); ctx.lineWidth = 1.1; ctx.stroke(ilium);
        ellipse(ctx, 86, 242, 5, 5, gray(8)); ellipse(ctx, 86, 242, 4, 4, gray(44));
        ellipse(ctx, 114, 242, 5, 5, gray(8)); ellipse(ctx, 114, 242, 4, 4, gray(44));
        strokePath(ctx, 'M81,238 Q86,235 91,238', gray(150), 0.6);  // hip joint fluid
        strokePath(ctx, 'M109,238 Q114,235 119,238', gray(150), 0.6);
    });

    // ── long bones: black cortex, dark marrow; joint fluid at shoulders/elbows/knees
    soft(v, 0.35, ctx => {
        const bones = [
            ['M57,94 Q48,120 46,157', 4.2], ['M143,94 Q152,120 154,157', 4.2],
            ['M45,170 Q42,200 38,227', 3.6], ['M155,170 Q158,200 162,227', 3.6],
            ['M86,248 Q84,280 83,313', 5.6], ['M114,248 Q116,280 117,313', 5.6],
            ['M82,323 Q81,352 80,383', 4.6], ['M118,323 Q119,352 120,383', 4.6],
        ];
        for (const [d, w] of bones) strokePath(ctx, d, gray(6), w);
        for (const [d, w] of bones) strokePath(ctx, d, gray(40), w * 0.5);
        for (const [x, y, r] of [[57, 91, 2.4], [143, 91, 2.4], [45, 164, 1.6], [155, 164, 1.6], [83, 318, 2.4], [117, 318, 2.4]]) {
            ellipse(ctx, x, y, r * 1.4, r * 0.5, gray(158));
        }
    });

    texture(v, 0.42);
}

// ─── axial slices (STIR, 200×200 units) ──────────────────────────────────────
// returns { x, y, k, skin } — lesion position / scale / nearest skin point
function drawAxial(v, region, rand) {
    const leftSide = region === 'larm' || region === 'lleg';

    if (region === 'head') {
        soft(v, 0.6, ctx => {
            ellipse(ctx, 100, 100, 74, 88, gray(120));   // scalp
            ellipse(ctx, 100, 100, 71, 85, gray(30));
            ellipse(ctx, 100, 100, 68, 82, gray(6));     // skull
            ellipse(ctx, 100, 100, 64, 78, gray(36));
            ellipse(ctx, 100, 100, 61, 75, gray(6));
            ellipse(ctx, 100, 100, 58.5, 72.5, gray(180)); // CSF
            ellipse(ctx, 100, 101, 56, 70, gray(118));     // grey matter
        });
        soft(v, 3, ctx => { ellipse(ctx, 86, 100, 28, 50, gray(72)); ellipse(ctx, 114, 100, 28, 50, gray(72)); });
        soft(v, 0.6, ctx => {
            strokePath(ctx, 'M100,30 L100,170', gray(196), 1.3);
            for (let i = 0; i < 40; i++) {
                const a = rand() * Math.PI * 2;
                const x = 100 + Math.cos(a) * 50, y = 100 + Math.sin(a) * 63;
                strokePath(ctx, `M${x},${y} L${100 + Math.cos(a) * 38},${100 + Math.sin(a) * 50}`, gray(168), 0.9);
            }
            ctx.save(); ctx.translate(100, 100);
            strokePath(ctx, 'M-6,-22 Q-12,0 -8,24 M6,-22 Q12,0 8,24', gray(206), 4.5);  // lateral ventricles
            ctx.restore();
        });
        texture(v, 0.4);
        const right = rand() > 0.5;
        return { x: right ? 138 : 62, y: 70 + rand() * 40, k: 1.6, skin: [right ? 172 : 28, 90] };
    }

    if (region === 'torso' || region === 'abdomen') {
        soft(v, 0.6, ctx => {
            ellipse(ctx, 100, 104, 94, 64, gray(130));   // skin
            ellipse(ctx, 100, 104, 92, 62, gray(32));    // fat (suppressed)
            ellipse(ctx, 100, 104, 86, 56, gray(90));    // muscle wall
        });
        if (region === 'torso') {
            soft(v, 1.2, ctx => {
                ellipse(ctx, 61, 98, 30, 38, gray(6));
                ellipse(ctx, 139, 98, 30, 38, gray(6));
            });
            soft(v, 0.4, ctx => {
                for (let i = 0; i < 40; i++) {
                    const side = i % 2 ? 1 : -1;
                    ellipse(ctx, 100 + side * (40 + rand() * 32), 70 + rand() * 60, 0.8 + rand(), 0.8 + rand(), gray(38));
                }
            });
            soft(v, 0.8, ctx => {
                ellipse(ctx, 106, 90, 20, 17, gray(84));       // heart
                ellipse(ctx, 101, 88, 8, 8, gray(16));
                ellipse(ctx, 113, 93, 7, 7, gray(18));
                ellipse(ctx, 88, 126, 7, 7, gray(10));         // descending aorta
            });
            soft(v, 0.4, ctx => {
                for (let i = 0; i < 14; i++) {                 // ribs
                    const a = Math.PI * (0.12 + (i % 7) * 0.12);
                    const side = i < 7 ? -1 : 1;
                    const x = 100 + side * Math.cos(a) * 82, y = 104 - Math.sin(a) * 52 + 10;
                    ellipse(ctx, x, y, 3, 2.4, gray(8)); ellipse(ctx, x, y, 1.6, 1.2, gray(40));
                }
            });
        } else {
            soft(v, 1.1, ctx => {
                ellipse(ctx, 66, 92, 36, 28, gray(62));        // liver
                ellipse(ctx, 140, 86, 14, 12, gray(110));      // spleen
                ellipse(ctx, 70, 134, 10, 13, gray(124));      // kidneys
                ellipse(ctx, 130, 134, 10, 13, gray(124));
                ellipse(ctx, 72, 134, 3, 5, gray(190));
                ellipse(ctx, 128, 134, 3, 5, gray(190));
                ellipse(ctx, 91, 128, 5, 5, gray(10));         // aorta / IVC
                ellipse(ctx, 108, 126, 6, 4, gray(20));
            });
            soft(v, 0.7, ctx => {
                for (let i = 0; i < 12; i++) {
                    const x = 96 + (rand() - 0.3) * 50, y = 84 + rand() * 30;
                    ellipse(ctx, x, y, 5 + rand() * 4, 4 + rand() * 3, gray(50 + rand() * 60));
                    ellipse(ctx, x, y, 1.5, 1.5, gray(160 + rand() * 40));
                }
            });
        }
        soft(v, 0.5, ctx => {                                  // vertebra + canal
            ellipse(ctx, 100, 142, 14, 12, gray(6)); ellipse(ctx, 100, 142, 12, 10, gray(44));
            ellipse(ctx, 100, 159, 6, 5, gray(184)); ellipse(ctx, 100, 159, 3, 3, gray(96));
            strokePath(ctx, 'M92,163 L86,170 M108,163 L114,170 M100,164 L100,172', gray(8), 3);
            ellipse(ctx, 80, 160, 12, 9, gray(96)); ellipse(ctx, 120, 160, 12, 9, gray(96));   // paraspinal muscles
        });
        texture(v, 0.42);
        return region === 'torso'
            ? { x: 132, y: 84, k: 1.7, skin: [186, 100] }
            : { x: 98, y: 98, k: 1.7, skin: [100, 42] };
    }

    // limbs
    const leg = region === 'lleg' || region === 'rleg';
    const R = leg ? 78 : 62;
    const side = leftSide ? 1 : -1;
    const bx = 100 - side * 6, by = 104;
    soft(v, 0.6, ctx => {
        ellipse(ctx, 100, 100, R, R * 0.94, gray(132));
        ellipse(ctx, 100, 100, R - 2, R * 0.94 - 2, gray(30));
        ellipse(ctx, 100, 100, R - 9, R * 0.94 - 9, gray(92));
    });
    soft(v, 0.4, ctx => {                                       // fascia between compartments
        for (let i = 0; i < 6; i++) {
            const a = (i / 6) * Math.PI * 2 + 0.3;
            strokePath(ctx, `M${bx + Math.cos(a) * 18},${by + Math.sin(a) * 18} Q${100 + Math.cos(a + 0.2) * (R * 0.6)},${100 + Math.sin(a + 0.2) * (R * 0.6)} ${100 + Math.cos(a) * (R - 10)},${100 + Math.sin(a) * (R * 0.94 - 10)}`, gray(150), 0.7);
        }
        ellipse(ctx, bx + side * 22, by - 18, 3, 3, gray(8));    // vessel flow voids
        ellipse(ctx, bx + side * 27, by - 15, 2.4, 2.4, gray(10));
        ellipse(ctx, bx + side * 25, by - 22, 1.8, 1.8, gray(120)); // nerve
    });
    soft(v, 0.35, ctx => {                                      // bone: black cortex, dark marrow
        ellipse(ctx, bx, by, leg ? 17 : 13, leg ? 16 : 12, gray(6));
        ellipse(ctx, bx, by, leg ? 10 : 7.5, leg ? 9.5 : 7, gray(46));
    });
    texture(v, 0.42);
    return { x: 100 + side * R * 0.42, y: 80 + rand() * 18, k: 1.7, skin: [100 + side * R, 96], bone: [bx, by, leg ? 17 : 13] };
}

// ─── injuries (STIR: oedema bright, metal = black blooming void) ─────────────
function oedema(v, x, y, r, rand, strength = 1) {
    soft(v, r * 0.35, ctx => {
        for (let i = 0; i < 9; i++) {
            const ox = x + (rand() - 0.5) * r * 0.9, oy = y + (rand() - 0.5) * r * 0.9;
            const rr = r * (0.35 + rand() * 0.45);
            const g = ctx.createRadialGradient(ox, oy, 0, ox, oy, rr);
            g.addColorStop(0, gray(235, 0.55 * strength));
            g.addColorStop(1, gray(235, 0));
            ctx.fillStyle = g;
            ctx.beginPath(); ctx.arc(ox, oy, rr, 0, Math.PI * 2); ctx.fill();
        }
    });
    // feathery intramuscular pattern
    soft(v, r * 0.06, ctx => {
        for (let i = 0; i < 10; i++) {
            const a = rand() * Math.PI;
            const len = r * (0.4 + rand() * 0.6);
            const cx = x + (rand() - 0.5) * r * 0.8, cy = y + (rand() - 0.5) * r * 0.8;
            strokePath(ctx, `M${cx - Math.cos(a) * len / 2},${cy - Math.sin(a) * len / 2} L${cx + Math.cos(a) * len / 2},${cy + Math.sin(a) * len / 2}`,
                gray(220, 0.35 * strength), r * 0.05);
        }
    });
}

function metal(v, x, y, size, rand) {
    // susceptibility "blooming": black void, bright pile-up crescent, distortion
    soft(v, size * 0.35, ctx => {
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(rand() * Math.PI);
        ellipse(ctx, 0, 0, size * 2.6, size * 1.9, gray(2));
        ctx.beginPath();
        ctx.ellipse(0, 0, size * 2.9, size * 2.2, 0, -0.9, 0.9);
        ctx.strokeStyle = gray(245, 0.9);
        ctx.lineWidth = size * 0.55;
        ctx.stroke();
        ctx.beginPath();
        ctx.ellipse(0, 0, size * 3.6, size * 2.8, 0, Math.PI - 0.6, Math.PI + 0.6);
        ctx.strokeStyle = gray(200, 0.45);
        ctx.lineWidth = size * 0.3;
        ctx.stroke();
        ctx.restore();
    });
}

function fractureLine(v, x, y, len, angle, rand) {
    const pts = [];
    for (let i = 0; i <= 8; i++) {
        const t = i / 8 - 0.5;
        pts.push([x + Math.cos(angle) * len * t + (rand() - 0.5) * len * 0.12, y + Math.sin(angle) * len * t + (rand() - 0.5) * len * 0.12]);
    }
    soft(v, len * 0.03, ctx => {
        ctx.beginPath();
        pts.forEach(([px, py], i) => (i ? ctx.lineTo(px, py) : ctx.moveTo(px, py)));
        ctx.strokeStyle = gray(2);
        ctx.lineWidth = len * 0.07;
        ctx.stroke();
    });
}

function drawInjury(v, cause, x, y, k, rand, extra = {}) {
    switch (cause) {
        case 'gunshot': {
            const [sx, sy] = extra.skin || [x + 14 * k, y - 6 * k];
            soft(v, 0.6 * k, ctx => strokePath(ctx, `M${sx},${sy} L${x},${y}`, gray(215, 0.8), 1.6 * k));  // wound track
            oedema(v, x, y, 12 * k, rand);
            metal(v, x, y, 1.9 * k, rand);
            break;
        }
        case 'melee':
            oedema(v, x, y, 15 * k, rand);
            soft(v, 1.2 * k, ctx => { ellipse(ctx, x, y, 5 * k, 3.5 * k, gray(170)); ellipse(ctx, x + k, y, 2.5 * k, 1.8 * k, gray(110)); });
            break;
        case 'fall':
        case 'vehicle': {
            const big = cause === 'vehicle';
            soft(v, 1.6 * k, ctx => ellipse(ctx, x, y, (big ? 6 : 4) * k, (big ? 13 : 10) * k, gray(205, 0.9)));   // marrow oedema
            if (big) oedema(v, x, y, 16 * k, rand, 0.8);
            fractureLine(v, x, y, (big ? 12 : 9) * k, 0.25 + rand() * 0.4, rand);
            break;
        }
        case 'explosion':
            oedema(v, x, y, 16 * k, rand);
            for (let i = 0; i < 6; i++) metal(v, x + (rand() - 0.5) * 24 * k, y + (rand() - 0.5) * 24 * k, (0.6 + rand() * 0.6) * k, rand);
            break;
        case 'fire': {
            const [sx, sy] = extra.skin || [x, y];
            const mx = (sx + x) / 2, my = (sy + y) / 2;
            soft(v, 1.4 * k, ctx => ellipse(ctx, mx, my, 16 * k, 4 * k, gray(220, 0.8), Math.atan2(sy - y, sx - x) + Math.PI / 2));
            break;
        }
        default:
            oedema(v, x, y, 11 * k, rand);
    }
}

// ─── scanner look: coil falloff, ghost, Rician noise ─────────────────────────
function scannerPost(canvas, seed) {
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    const img = ctx.getImageData(0, 0, CW, CW);
    const d = img.data;
    const src = new Float32Array(CW * CW);
    for (let i = 0, p = 0; p < src.length; i += 4, p++) src[p] = d[i];

    const rand = rng(seed);
    const ghostShift = Math.round(CW * 0.11);
    const cx = CW * 0.5, cy = CW * 0.46, sig2 = 2 * (CW * 0.62) ** 2;
    const sigma = 6.5;

    for (let y = 0, p = 0; y < CW; y++) {
        const gy = (y + ghostShift) % CW;
        for (let x = 0; x < CW; x++, p++) {
            let s = src[p] + src[gy * CW + x] * 0.045;                      // phase-encode ghost
            s *= 0.78 + 0.34 * Math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / sig2); // coil sensitivity
            // Rician noise: |s + n1 + i·n2|
            const u1 = rand() || 1e-6, u2 = rand();
            const m = Math.sqrt(-2 * Math.log(u1)) * sigma;
            const n1 = m * Math.cos(2 * Math.PI * u2), n2 = m * Math.sin(2 * Math.PI * u2);
            const v = Math.min(255, Math.sqrt((s + n1) ** 2 + n2 * n2));
            const i = p * 4;
            d[i] = d[i + 1] = d[i + 2] = v;
        }
    }
    ctx.putImageData(img, 0, 0);
}

// DICOM-style overlay text + scale bar (in pixels, after post-processing)
// px = length of 5 cm in canvas pixels
function scannerText(canvas, lines, px) {
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.font = '22px Consolas, monospace';
    ctx.fillStyle = 'rgba(230,240,245,0.85)';
    ctx.textAlign = 'right';
    lines.forEach((t, i) => ctx.fillText(t, CW - 18, 34 + i * 26));

    // 5 cm scale bar
    const x2 = CW - 24, x1 = x2 - px, y = CW - 26;
    ctx.strokeStyle = 'rgba(230,240,245,0.85)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x1, y); ctx.lineTo(x2, y);
    for (let i = 0; i <= 5; i++) { const tx = x1 + (px * i) / 5; ctx.moveTo(tx, y); ctx.lineTo(tx, y - (i % 5 ? 6 : 12)); }
    ctx.stroke();
    ctx.textAlign = 'center';
    ctx.font = '18px Consolas, monospace';
    ctx.fillText('5 cm', (x1 + x2) / 2, y - 16);
}

function redArrow(canvas, x1, y1, x2, y2) {
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.strokeStyle = '#ff2e2e';
    ctx.fillStyle = '#ff2e2e';
    ctx.lineWidth = 5;
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
    const a = Math.atan2(y2 - y1, x2 - x1);
    ctx.beginPath();
    ctx.moveTo(x2, y2);
    ctx.lineTo(x2 - Math.cos(a - 0.4) * 26, y2 - Math.sin(a - 0.4) * 26);
    ctx.lineTo(x2 - Math.cos(a + 0.4) * 26, y2 - Math.sin(a + 0.4) * 26);
    ctx.closePath();
    ctx.fill();
}

function redRing(canvas, x, y, r) {
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.strokeStyle = '#ff2e2e';
    ctx.lineWidth = 3;
    ctx.setLineDash([10, 7]);
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke();
    ctx.setLineDash([]);
}

// ─── the three views ─────────────────────────────────────────────────────────
function renderViews(scan) {
    const seed = `${scan.name}|${scan.date}`;
    const region = scan.region || 'torso';
    const anchor = ANCHORS[region];
    const jr = rng(seed + '|jitter');
    const lx = anchor[0] + (jr() - 0.5) * 5, ly = anchor[1] + (jr() - 0.5) * 7;
    const notes = NOTES[scan.cause] || NOTES.unknown;
    const lesionOnRight = lx > 100;   // viewer right → note goes left
    const injured = !!scan.region;

    // v1 — whole body (body is 200×400 units, centred in a 400-unit square)
    const c1 = document.getElementById('v1');
    const v1 = view(c1, -100, 0, 400);
    drawCoronal(v1, rng(seed + '|anat'));
    if (injured) drawInjury(v1, scan.cause, lx, ly, 1, rng(seed + '|inj'));
    scannerPost(c1, seed + '|n1');
    // coronal body: ~180 cm over 400 units → 5 cm ≈ 11.1 units
    scannerText(c1, ['STIR COR', 'TR 4200 TE 60', 'SL 6.0mm'], 11.1 * CW / 400);
    if (injured) { const [px, py] = v1.toPx(lx, ly); redRing(c1, px, py, 44); }

    // v2 — coronal detail of the region
    const c2 = document.getElementById('v2');
    const size = DETAIL_SIZE[region];
    const v2 = view(c2, anchor[0] - size / 2, anchor[1] - size / 2, size);
    drawCoronal(v2, rng(seed + '|anat'));
    if (injured) drawInjury(v2, scan.cause, lx, ly, 1, rng(seed + '|inj'));
    scannerPost(c2, seed + '|n2');
    scannerText(c2, ['STIR COR', 'FOV ' + Math.round(size * 4.5) + 'mm', 'SL 3.0mm'], 11.1 * CW / size);
    const note2 = document.getElementById('note2');
    if (injured) {
        const [px, py] = v2.toPx(lx, ly);
        const sx = lesionOnRight ? CW * 0.28 : CW * 0.72, sy = CW * 0.3;
        redArrow(c2, sx, sy, px + (lesionOnRight ? -24 : 24), py - 20);
        placeNote(note2, notes[0], lesionOnRight, false);
    } else {
        placeNote(note2, 'No focal abnormality', false, true);
    }

    // v3 — axial slice
    const c3 = document.getElementById('v3');
    const v3 = view(c3, 0, 0, 200);
    const ax = drawAxial(v3, region, rng(seed + '|axial'));
    const note3 = document.getElementById('note3');
    if (injured) {
        drawInjury(v3, scan.cause, ax.x, ax.y, ax.k, rng(seed + '|inj3'), { skin: ax.skin });
    }
    scannerPost(c3, seed + '|n3');
    // axial slices: units per 5 cm differ per body part (thigh ≈ 16 cm, chest ≈ 34 cm, head ≈ 16 cm wide)
    const AXIAL_5CM = { head: 46, torso: 28, abdomen: 28, rarm: 62, larm: 62, rleg: 50, lleg: 50 };
    scannerText(c3, ['STIR AX', 'TR 3800 TE 55', 'SL 4.0mm'], AXIAL_5CM[region] * CW / 200);
    if (injured) {
        const [px, py] = v3.toPx(ax.x, ax.y);
        const right = ax.x > 100;
        redArrow(c3, right ? CW * 0.26 : CW * 0.74, CW * 0.2, px + (right ? -18 : 18), py - 16);
        placeNote(note3, notes[1], right, false);
    } else {
        placeNote(note3, 'Normal signal', false, true);
    }

    const name = REGION_NAMES[region];
    document.getElementById('cap1').textContent = 'MRI STIR — WHOLE BODY (CORONAL VIEW)';
    document.getElementById('cap2').textContent = `MRI STIR — ${name} (CORONAL DETAIL)`;
    document.getElementById('cap3').textContent = `MRI STIR — ${name} (AXIAL VIEW)`;
}

// note text sits on the side opposite the lesion, upper area of the panel
function placeNote(node, text, leftSide, ok) {
    node.textContent = text;
    node.className = ok ? 'note ok' : 'note';
    node.style.top = ok ? '44%' : '13%';
    node.style.left = ok ? '27%' : (leftSide ? '4%' : '50%');
    node.style.right = 'auto';
}

// ─── text parts ──────────────────────────────────────────────────────────────
function fillMeta(dl, rows) {
    dl.innerHTML = '';
    for (const [label, value, strong] of rows) {
        const dt = document.createElement('dt');
        dt.textContent = label;
        const dd = document.createElement('dd');
        dd.textContent = value ?? '—';
        if (strong) dd.className = 'strong';
        dl.append(dt, dd);
    }
}

function fillList(id, items) {
    const ul = document.getElementById(id);
    ul.innerHTML = '';
    (items && items.length ? items : ['—']).forEach(text => {
        const li = document.createElement('li');
        li.textContent = text;
        ul.appendChild(li);
    });
}

// ─── whole sheet → one JPEG (for the Discord log) ────────────────────────────
// Walks the laid-out DOM and repaints it onto a 1390×1080 canvas at the same
// positions, using each element's computed font/colour. Scan canvases are
// copied in directly.
function sheetToJpeg() {
    const out = document.createElement('canvas');
    out.width = 1390;
    out.height = 1080;
    const ctx = out.getContext('2d');
    const base = sheet.getBoundingClientRect();
    const scale = base.width / 1390;
    const rect = (node) => {
        const r = node.getBoundingClientRect();
        return { x: (r.left - base.left) / scale, y: (r.top - base.top) / scale, w: r.width / scale, h: r.height / scale };
    };

    const bg = ctx.createLinearGradient(0, 0, 0, 1080);
    bg.addColorStop(0, '#0b1a2a');
    bg.addColorStop(1, '#071320');
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, 1390, 1080);

    const fillBox = (node, color, border) => {
        const r = rect(node);
        if (color) { ctx.fillStyle = color; ctx.fillRect(r.x, r.y, r.w, r.h); }
        if (border) { ctx.strokeStyle = border; ctx.lineWidth = 1; ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1); }
    };

    // text: wraps inside the element box with its own computed style
    const drawText = (node, opts = {}) => {
        const text = (node.textContent || '').trim();
        if (!text) return;
        const cs = getComputedStyle(node);
        const r = rect(node);
        const size = parseFloat(cs.fontSize);
        const lineH = parseFloat(cs.lineHeight) || size * 1.3;
        ctx.font = `${cs.fontStyle} ${cs.fontWeight} ${size}px ${cs.fontFamily}`;
        ctx.fillStyle = opts.color || cs.color;
        ctx.textBaseline = 'top';
        const align = opts.align || cs.textAlign;
        ctx.textAlign = align === 'center' ? 'center' : (align === 'right' || align === 'end') ? 'right' : 'left';
        const padL = parseFloat(cs.paddingLeft) || 0, padR = parseFloat(cs.paddingRight) || 0, padT = parseFloat(cs.paddingTop) || 0;
        const maxW = Math.max(10, r.w - padL - padR);

        const lines = [];
        let line = '';
        for (const word of text.split(/\s+/)) {
            const test = line ? `${line} ${word}` : word;
            if (ctx.measureText(test).width > maxW && line) { lines.push(line); line = word; } else line = test;
        }
        lines.push(line);

        const x = ctx.textAlign === 'center' ? r.x + padL + maxW / 2 : ctx.textAlign === 'right' ? r.x + r.w - padR : r.x + padL;
        const textBlockH = lines.length * lineH;
        let y = r.y + padT + Math.max(0, (r.h - padT * 2 - textBlockH) / 2) * (opts.vcenter ? 1 : 0) + (lineH - size) / 2;
        if (opts.shadow) { ctx.shadowColor = '#000'; ctx.shadowBlur = 6; }
        for (const l of lines) { ctx.fillText(l, x, y); y += lineH; }
        ctx.shadowBlur = 0;
    };

    // header
    const header = sheet.querySelector('header');
    const hr = rect(header);
    ctx.fillStyle = '#23476a';
    ctx.fillRect(hr.x, hr.y + hr.h - 1, hr.w, 1);
    const logo = rect(sheet.querySelector('.logo'));
    ctx.save();
    ctx.translate(logo.x + (logo.w - logo.h * 64 / 64) / 2, logo.y);
    ctx.scale(logo.h / 64, logo.h / 64);
    ctx.lineWidth = 4; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
    ctx.strokeStyle = '#5ab4e6'; ctx.stroke(new Path2D('M4 50 L20 18 L30 34 L40 10 L60 50'));
    ctx.strokeStyle = '#e8f4fb'; ctx.stroke(new Path2D('M26 44 h12 M32 38 v12'));
    ctx.restore();
    ['#hosp', '#sub', '#dept'].forEach(id => drawText(sheet.querySelector(id)));
    sheet.querySelectorAll('.meta').forEach(dl => {
        const r = rect(dl);
        ctx.fillStyle = '#23476a';
        ctx.fillRect(r.x, r.y, 1, r.h);
        dl.querySelectorAll('dt, dd').forEach(n => drawText(n));
    });

    // scan panels
    sheet.querySelectorAll('.panel').forEach(panel => {
        fillBox(panel, '#000', '#2a3f55');
        const canvas = panel.querySelector('canvas');
        const f = rect(panel.querySelector('.frame'));
        const s = Math.max(f.w / canvas.width, f.h / canvas.height);           // object-fit: cover
        const sw = f.w / s, sh = f.h / s;
        ctx.drawImage(canvas, (canvas.width - sw) / 2, (canvas.height - sh) / 2, sw, sh, f.x, f.y, f.w, f.h);

        const m = rect(panel.querySelector('.rmark'));
        ctx.fillStyle = 'rgba(0,0,0,0.55)';
        ctx.beginPath(); ctx.arc(m.x + m.w / 2, m.y + m.h / 2, m.w / 2 - 1, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.stroke();
        drawText(panel.querySelector('.rmark'), { align: 'center', vcenter: true });

        const note = panel.querySelector('.note');
        if (note && note.textContent) drawText(note, { shadow: true });
        const cap = panel.querySelector('figcaption');
        fillBox(cap, '#0a1622');
        ctx.fillStyle = '#2a3f55';
        const cr = rect(cap);
        ctx.fillRect(cr.x, cr.y, cr.w, 1);
        drawText(cap, { vcenter: true });
    });

    // findings / observations / conclusion
    sheet.querySelectorAll('.box').forEach(box => {
        fillBox(box, 'rgba(8,20,33,0.7)', '#1d3a57');
        const h3 = box.querySelector('h3');
        fillBox(h3, '#12355a');
        drawText(h3, { vcenter: true });
        box.querySelectorAll('li').forEach(li => {
            const r = rect(li);
            const cs = getComputedStyle(li);
            ctx.font = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
            ctx.fillStyle = cs.color;
            ctx.textAlign = 'left';
            ctx.fillText('•', r.x - 16, r.y + (parseFloat(cs.lineHeight) - parseFloat(cs.fontSize)) / 2);
            drawText(li);
        });
    });

    // signature
    drawText(sheet.querySelector('#sig'), { align: 'right' });
    const line = rect(sheet.querySelector('.sig-line'));
    ctx.fillStyle = '#3f6a91';
    ctx.fillRect(line.x, line.y, line.w, 1);
    ['#signame', '#sigtitle', '#sighosp', '#sigdate'].forEach(id => drawText(sheet.querySelector(id), { align: 'right' }));

    return out.toDataURL('image/jpeg', 0.86);
}

async function uploadSheet(token) {
    try { await document.fonts.ready; } catch (e) { /* fonts optional */ }
    const image = sheetToJpeg();
    if (inGame) {
        fetch(`https://${GetParentResourceName()}/mriImage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ token, image }),
        }).catch(() => {});
    } else {
        window.__lastSheetJpeg = image;   // browser preview: inspect via devtools
    }
}

function render(scan, uploadToken) {
    const dateOnly = (scan.date || '').split(' ')[0];

    document.getElementById('hosp').textContent = scan.hospital || 'PILLBOX HILL';
    document.getElementById('sub').textContent = scan.subtitle || 'MEDICAL CENTER';
    document.getElementById('dept').textContent = scan.department || 'Emergency & Radiology Department';

    fillMeta(document.getElementById('meta-patient'), [
        ['Patient Name:', scan.name, true],
        ['Date of Birth:', scan.dob ? `${scan.dob}${scan.age != null ? `   (Age ${scan.age})` : ''}` : 'Unknown'],
        ['Scan Date:', scan.date],
        ['Patient ID:', scan.patientId],
    ]);
    fillMeta(document.getElementById('meta-study'), [
        ['Study Type:', scan.studyType || 'MRI SERIES'],
        ['Indication:', scan.indication || 'Routine examination'],
        ['Operator:', scan.operator],
        ['Department:', scan.deptLabel || 'Radiology'],
        ['Accession No:', scan.accession],
    ]);

    // show the sheet first, render the (heavier) scans on the next frame
    fit();
    root.classList.remove('hidden');
    requestAnimationFrame(() => {
        renderViews(scan);
        root.classList.remove('revealing');
        void root.offsetWidth;
        root.classList.add('revealing');
        // text below is filled synchronously, so it's laid out by the next frame
        if (uploadToken) requestAnimationFrame(() => uploadSheet(uploadToken));
    });

    document.getElementById('ftitle').textContent = `FINDINGS — ${REGION_NAMES[scan.region] || 'WHOLE BODY'}`;
    fillList('findings', scan.findings);
    fillList('observations', scan.observations || (scan.impression ? [scan.impression] : []));
    fillList('conclusion', scan.conclusion || (scan.impression ? [scan.impression] : []));

    const op = scan.operator || 'On-duty staff';
    document.getElementById('sig').textContent = op;
    document.getElementById('signame').textContent = op;
    document.getElementById('sigtitle').textContent = scan.signatureTitle || 'Radiology Operator';
    document.getElementById('sighosp').textContent =
        `${scan.hospital || 'Pillbox Hill'} ${scan.subtitle || 'Medical Center'}`.replace(/\b\w+/g, w => w[0] + w.slice(1).toLowerCase());
    document.getElementById('sigdate').textContent = dateOnly;
}

// scale the fixed 1390×1080 sheet to the screen
function fit() {
    const scale = Math.min(window.innerWidth * 0.96 / 1390, window.innerHeight * 0.96 / 1080);
    sheet.style.transform = `scale(${scale})`;
}
window.addEventListener('resize', fit);

// ─── NUI plumbing ────────────────────────────────────────────────────────────
const inGame = typeof GetParentResourceName === 'function';

function close() {
    if (root.classList.contains('hidden')) return;
    root.classList.add('hidden');
    if (inGame) {
        fetch(`https://${GetParentResourceName()}/mriClose`, { method: 'POST', body: '{}' }).catch(() => {});
    }
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'mriShow' && data.scan) render(data.scan, data.uploadToken);
    if (data.action === 'mriHide') close();
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
document.getElementById('close').addEventListener('click', close);

// Opened in a normal browser (not FiveM): show a sample so the look can be checked.
if (!inGame) {
    document.body.style.background = '#202428';
    render({
        hospital: 'PILLBOX HILL', subtitle: 'MEDICAL CENTER', department: 'Emergency & Radiology Department',
        studyType: 'MRI SERIES', deptLabel: 'Radiology', signatureTitle: 'Radiology Operator',
        name: 'Stafan Botha', dob: '2000-01-05', age: 26, date: '2026-09-26 18:29',
        patientId: 'PHMC-482913', accession: 'PHMC-MRI-260926-182911',
        indication: 'Gunshot wound (left leg)', operator: 'Pienkie Jacobs',
        severity: 'Moderate', health: 47, region: 'lleg', regionLabel: 'left leg', cause: 'gunshot',
        findings: [
            'Metallic foreign body (projectile fragment) lodged in the left leg.',
            'Susceptibility artefact surrounding the metallic fragment.',
            'Surrounding oedema within the left leg soft tissues.',
            'No secondary projectile tract identified.',
        ],
        observations: [
            'Overall condition graded moderate (47% vital capacity).',
            'No other acute abnormality identified elsewhere in the study.',
        ],
        conclusion: [
            'Metallic foreign body (projectile fragment) lodged in the left leg.',
            'Significant trauma. Admission and observation advised.',
            'Admit for observation. Repeat imaging in 24 hours.',
        ],
    });
}
