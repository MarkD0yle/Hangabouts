// Snuffler, drawn by Metal. Spec 006.
// Ported line for line from <script id="fs"> in snuffler-hanging.html. Keep the two in step until M5.
// Compiled at runtime by SnufflerRenderer (device.makeLibrary(source:)); there is no build step.
//
// Two passes:
//   1. snuffler_fragment  the 3D model, as distance fields. Writes premultiplied colour.
//   2. composite_fragment adds the drop shadow the page got from CSS
//                         (filter: drop-shadow(1px 4px 4px rgba(20,12,4,.33))).

#include <metal_stdlib>
using namespace metal;

// Must match SnufflerUniforms in Swift exactly: uRes first, then the floats in this order.
struct Uniforms {
    float2 uRes;
    float uYaw, uSwing, uSignSwing, uSignYaw, uBlink, uKick, uTail, uSniff, uFail, uBreathe;
    float uRaiseR, uRaiseL, uShakeR, uShakeL, uTired;
    float uBody, uGrip;   // his body's sway about the gripping hand; which hand grips (1 right, -1 left)
};

struct VOut { float4 position [[position]]; };

// One full-screen quad, as a 4-vertex triangle strip. No vertex buffer.
vertex VOut quad_vertex(uint vid [[vertex_id]]) {
    VOut o;
    o.position = float4(float(vid & 1u) * 2. - 1., float(vid >> 1u) * 2. - 1., 0., 1.);
    return o;
}

// ---------- GLSL-style helpers ----------
// GLSL's smoothstep is used with edge0 > edge1 all over the model. Spell the formula out so it can't differ.
static inline float glsl_smoothstep(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0., 1.); return t * t * (3. - 2. * t); }
#define smoothstep glsl_smoothstep
// GLSL's mat2(c,-s,s,c) is column-major; so is float2x2(float2, float2).
static inline float2x2 rot(float a) { float c = cos(a), s = sin(a); return float2x2(float2(c, -s), float2(s, c)); }

static inline float smin(float a, float b, float k) { float h = clamp(.5 + .5*(b-a)/k, 0., 1.); return mix(b, a, h) - k*h*(1.-h); }
static inline float sdEll(float3 p, float3 r) { float k0 = length(p/r); float k1 = length(p/(r*r)); return k0*(k0-1.)/k1; }
static inline float sdCap(float3 p, float3 a, float3 b, float r1, float r2) {
    float3 pa = p-a, ba = b-a; float h = clamp(dot(pa,ba)/dot(ba,ba), 0., 1.);
    return length(pa - ba*h) - mix(r1, r2, h);
}
static inline float sdBox(float3 p, float3 b, float r) { float3 q = abs(p)-b; return length(max(q,0.)) + min(max(q.x,max(q.y,q.z)),0.) - r; }

// The swing: two ropes from the top centre of the page down to a bar. Everything swings about the top.
// The ropes meet at one point, so the swing twists with him when he turns.
constant float BAR = .46;                       // how far the bar hangs below the top
constant float ARM = .25;                       // shorter hanging arm than the app: his body sits this much closer to the bar

constant float3 HEAD = float3(0., -.93, .06);
constant float3 EYE_L = float3(-.21, -.805, .36);   // big eye, with the monocle (his left, the near side when he faces right)
constant float3 EYE_R = float3( .20, -.825, .37);

// returns (distance, material). 1 fur, 3 nose, 4 eye, 5 gold, 6 bag, 7 strap, 8 card, 9 dark, 10 rope, 11 wood
static inline float2 U(float2 a, float2 b) { return a.x < b.x ? a : b; }

// Fur: value noise stretched along y, so it reads as strands that hang downward. It moves with his body.
static inline float hash3(float3 p) { p = fract(p*.3183099 + .1); p *= 17.; return fract(p.x*p.y*p.z*(p.x + p.y + p.z)); }
static float vnoise(float3 x) {
    float3 i = floor(x), f = fract(x); f = f*f*(3. - 2.*f);
    return mix(mix(mix(hash3(i), hash3(i + float3(1.,0.,0.)), f.x), mix(hash3(i + float3(0.,1.,0.)), hash3(i + float3(1.,1.,0.)), f.x), f.y),
               mix(mix(hash3(i + float3(0.,0.,1.)), hash3(i + float3(1.,0.,1.)), f.x), mix(hash3(i + float3(0.,1.,1.)), hash3(i + float3(1.,1.,1.)), f.x), f.y), f.z);
}

// GLSL has global uniforms; Metal doesn't. The model lives in a struct that holds them,
// so the functions below read the same as the GLSL.
#define uYaw       un.uYaw
#define uSwing     un.uSwing
#define uSignSwing un.uSignSwing
#define uSignYaw   un.uSignYaw
#define uBlink     un.uBlink
#define uKick      un.uKick
#define uTail      un.uTail
#define uSniff     un.uSniff
#define uFail      un.uFail
#define uBreathe   un.uBreathe
#define uRaiseR    un.uRaiseR
#define uRaiseL    un.uRaiseL
#define uShakeR    un.uShakeR
#define uShakeL    un.uShakeL
#define uTired     un.uTired
#define uBody      un.uBody
#define uGrip      un.uGrip

struct Snuffler {
    Uniforms un;

    // world -> the swing's space (bar at y = 0). The ropes and bar use this.
    float3 toSwing(float3 p) { p.xy = rot(uSwing)*p.xy; p.y += BAR; p.xz = rot(-uYaw)*p.xz; return p; }
    // world -> his body. His body also sways about the hand that grips the bar, lagging behind the swing.
    float3 toLocal(float3 p) {
        p.xy = rot(uSwing)*p.xy; p.y += BAR;
        float gx = uGrip*.56*cos(uYaw);           // the gripping hand, seen from the front
        p.x -= gx; p.xy = rot(uBody)*p.xy; p.x += gx;
        p.y -= ARM; p.xz = rot(-uYaw)*p.xz; return p;
    }

    float3 noseTip() { return float3(uSniff*.05, -1.49 + abs(uSniff)*.02, .79); }
    // the sign hangs from the nose and always turns to face the viewer
    float3 toSign(float3 p) {
        float3 q = p - (noseTip() + float3(0., -.09, 0.));
        q.xz = rot(uYaw + uSignYaw)*q.xz;
        q.xy = rot(uSignSwing)*q.xy;
        return q;
    }

    // one arm. side 1 = his right, -1 = his left (mirrored). r: 0 down by his side, 1 up gripping the bar.
    // k: a shake of a hand that has just let go. On the way up or down the arm swings out wide.
    float arm(float3 p, float side, float r, float k) {
        float wide = .26*sin(3.14159*r);
        float3 q = float3(p.x*side, p.y, p.z);
        float3 S = mix(float3(.46,-1.16,.04), float3(.48,-1.20,0.), r);
        float3 E = mix(float3(.51,-1.34,.09), float3(.60,-.76,0.), r) + float3(wide*.6, 0., 0.);
        float3 H = mix(float3(.55,-1.54,.14), float3(.56,-.03-ARM,0.), r) + float3(wide + .05*k, 0., .05*k);
        float d = sdCap(q, S, E, .105, .095);
        d = smin(d, sdCap(q, E, H, .095, .09), .08);
        return smin(d, length(q - H) - mix(.105, .128, r), .05);
    }
    float droop() { return max(uFail, .6*uTired); }

    float2 map(float3 pw) {
        float3 p = toLocal(pw);
        float3 pb = toSwing(pw);                     // swing space: the bar at y = 0
        float br = 1. + uBreathe;
        float d = sdEll(p - float3(0., -1.50, -.02), float3(.50*br, .54, .47*br));
        d = smin(d, length(p - HEAD) - .40, .15);
        // arms: one hangs from the bar, the other rests by his side. He swaps them when one gets tired.
        d = smin(d, arm(p, 1., uRaiseR, uShakeR), .09);
        d = smin(d, arm(p, -1., uRaiseL, uShakeL), .09);
        // ears (they droop when he's failed)
        float3 pe = p; pe.x = abs(pe.x);
        d = smin(d, sdEll(pe - float3(.33 + .04*droop(), -.63 - .09*droop(), -.02), float3(.15,.15,.10)), .06);
        // hair tuft
        d = smin(d, sdCap(p, float3(-.03,-.55,.06), float3(-.07,-.42,.13), .036, .024), .04);
        d = smin(d, sdCap(p, float3(.04,-.55,.04), float3(.07,-.43,.10), .036, .024), .04);
        // legs and feet
        float3 pl = p - float3(0., -1.93, 0.); pl.yz = rot(uKick)*pl.yz; pl.x = abs(pl.x);
        d = smin(d, sdCap(pl, float3(.20,0.,0.), float3(.22,-.17,.02), .115, .105), .10);
        d = smin(d, sdEll(pl - float3(.23,-.25,.10), float3(.135,.095,.19)), .07);
        // snout: three tapering segments, forward then down
        float3 s0 = float3(0.,-1.03,.30), s1 = float3(0.,-1.04,.60), s2 = float3(uSniff*.02,-1.25,.79), s3 = noseTip();
        d = smin(d, sdCap(p, s0, s1, .205, .175), .12);
        d = smin(d, sdCap(p, s1, s2, .175, .145), .09);
        d = smin(d, sdCap(p, s2, s3, .145, .118), .08);
        // tail: curls up behind him
        float3 pt = p - float3(0., -1.80, -.33); pt.yz = rot(uTail)*pt.yz;
        float tl = sdCap(pt, float3(0.), float3(0.,.00,-.34), .095, .088);
        tl = smin(tl, sdCap(pt, float3(0.,.00,-.34), float3(0.,.26,-.48), .088, .08), .06);
        tl = smin(tl, sdCap(pt, float3(0.,.26,-.48), float3(0.,.43,-.32), .08, .074), .06);
        tl = smin(tl, sdCap(pt, float3(0.,.43,-.32), float3(0.,.36,-.19), .074, .07), .06);
        d = smin(d, tl, .08);
        float2 res = float2(d, 1.);

        res = U(res, float2(length(p - (s3 + float3(0.,-.04,.01))) - .125, 3.));
        res = U(res, float2(length(p - EYE_L) - .135, 4.));
        res = U(res, float2(length(p - EYE_R) - .092, 4.));
        // monocle: a gold ring standing just off the big eye
        float3 f = normalize(EYE_L - HEAD);
        float3 qm = p - (EYE_L + f*.075); float h = dot(qm, f);
        res = U(res, float2(length(float2(length(qm - f*h) - .16, h)) - .024, 5.));
        // brows
        float tilt = .07*uFail;
        res = U(res, float2(sdCap(p, float3(-.35,-.625+tilt,.27), float3(-.11,-.605-tilt,.43), .024, .024), 9.));
        res = U(res, float2(sdCap(p, float3(.13,-.70-tilt,.42), float3(.29,-.71+tilt,.32), .02, .02), 9.));
        // satchel on his left hip, strap over the right shoulder
        float3 qs = p - float3(0., -1.40, -.02); qs.xy = rot(-.78)*qs.xy; qs.z *= 1.08;
        res = U(res, float2((length(float2(length(qs.xz) - .50, qs.y*.6)) - .022)*.85, 7.));
        res = U(res, float2(sdBox(p - float3(-.58,-1.68,.0), float3(.045,.085,.135), .085), 6.));
        res = U(res, float2(sdBox(p - float3(-.60,-1.50,-.03), float3(.008,.07,.09), .006), 8.));
        // string and sign
        float3 q = toSign(p);
        res = U(res, float2(sdCap(q, float3(0.), float3(0.,-.2,0.), .012, .012), 9.));
        res = U(res, float2(sdBox(q - float3(0.,-.47,0.), float3(.22,.195,.018), .07), 8.));
        // the swing: ropes from the top centre to each end of the bar
        float3 ps = pb; ps.x = abs(ps.x);
        res = U(res, float2(sdCap(ps, float3(.03,BAR+.02,0.), float3(.64,0.,0.), .02, .02), 10.));
        res = U(res, float2(sdCap(ps, float3(0.,0.,0.), float3(.72,0.,0.), .042, .042), 11.));
        res = U(res, float2(length(ps - float3(.72,0.,0.)) - .06, 11.));
        return res;
    }

    float fur(float3 pw) {
        float3 p = toLocal(pw);
        return .65*vnoise(p*float3(46.,11.,46.)) + .35*vnoise(p*float3(97.,23.,97.) + 7.);
    }

    float3 calcN(float3 p) {
        float2 e = float2(.0015, -.0015);
        return normalize(e.xyy*map(p+e.xyy).x + e.yyx*map(p+e.yyx).x + e.yxy*map(p+e.yxy).x + e.xxx*map(p+e.xxx).x);
    }
    float shadow(float3 ro, float3 rd) {
        float res = 1., t = .03;
        for (int i = 0; i < 22; i++) {
            float h = map(ro + rd*t).x;
            res = min(res, 9.*h/t);
            t += clamp(h, .02, .16);
            if (res < .02 || t > 1.8) break;
        }
        return clamp(res, 0., 1.);
    }
    float ao(float3 p, float3 n) {
        float o = 0., s = 1.;
        for (int i = 1; i <= 4; i++) { float h = .045*float(i); o += (h - map(p + n*h).x)*s; s *= .62; }
        return clamp(1. - 2.4*o, 0., 1.);
    }

    // "?" and "!" as 2D shapes on the card
    float glyph(float2 u) {
        float dotd = length(u - float2(0.,-.145)) - .036;
        float2 c = u - float2(0., .065);
        float hook = max(abs(length(c) - .078) - .028, -max(c.x, c.y + .01));
        float stem = length(float2(u.x, u.y - clamp(u.y, -.07, -.013))) - .028;
        float qm = min(min(hook, stem), dotd);
        float bang = min(length(float2(u.x, u.y - clamp(u.y, -.05, .13))) - mix(.022, .04, clamp((u.y+.05)/.18, 0., 1.)), dotd);
        return mix(qm, bang, step(.5, uFail));
    }

    void shade(float3 pw, float3 n, float m, thread float3 &alb, thread float &gloss, thread float &specAmt) {
        float3 p = toLocal(pw);
        gloss = 12.; specAmt = .10;
        if (m < 1.5) {
            alb = float3(.90, .62, .17);
            // belly patch
            float b = sdEll(p - float3(0., -1.58, .42), float3(.31, .39, .20));
            alb = mix(alb, float3(1., .88, .58), smoothstep(.03, -.04, b));
            // snout darkens toward the tip
            float sn = smoothstep(.36, .9, p.z) * step(-1.72, p.y) * step(p.y, -.82);
            alb = mix(alb, float3(.62, .38, .10), sn*.85);
            // ringed tail
            if (p.z < -.36 && p.y > -1.95 && p.y < -1.2) {
                float a = atan2(p.y + 1.60, p.z + .66);
                alb = mix(float3(.80,.52,.14), float3(.42,.25,.07), smoothstep(-.15, .15, sin(a*6.5)));
            }
            // pink inside the ears, blush on the cheeks
            float2 ec = float2(abs(p.x) - (.33 + .04*droop()), p.y + .63 + .09*droop());
            alb = mix(alb, float3(.96,.55,.48), smoothstep(.105, .065, length(ec)) * step(.0, p.z) * step(abs(p.x), .47));
            alb = mix(alb, float3(.97,.55,.45), .45*smoothstep(.14, .03, length(float3(abs(p.x)-.31, p.y+1.03, p.z-.26))));
        } else if (m < 3.5) {
            alb = float3(.07,.04,.03); gloss = 60.; specAmt = .9;
        } else if (m < 4.5) {
            bool big = p.x < 0.;
            float3 c = big ? EYE_L : EYE_R; float r = big ? .135 : .092;
            float3 fwd = normalize(float3(big ? -.38 : .34, .02, 1.));
            float a = dot(normalize(p - c), fwd);
            alb = float3(.97,.96,.93);
            alb = mix(alb, mix(float3(.82,.48,.14), float3(.38,.19,.05), smoothstep(.86,.80,a)), smoothstep(.79,.81,a));
            alb = mix(alb, float3(.02), smoothstep(.925,.94,a));
            gloss = 90.; specAmt = 1.;
            // eyelid: closes on a blink, half closed when failed
            float lid = mix(1.3, -1.2, uBlink);
            if (big) lid = min(lid, mix(1.3, .22, uFail));
            lid = min(lid, mix(1.3, .3, uTired));    // heavy lids while he swaps arms
            if ((p.y - c.y)/r > lid) { alb = float3(.84,.57,.16); gloss = 12.; specAmt = .1; }
        } else if (m < 5.5) {
            alb = float3(.93,.70,.22); gloss = 50.; specAmt = 1.2;
        } else if (m < 6.5) {
            alb = mix(float3(.33,.46,.28), float3(.45,.60,.38), smoothstep(-1.67, -1.61, p.y));
            alb = mix(alb, float3(.93,.76,.28), smoothstep(.03,.02, length(float2(p.y+1.67, p.z-.0))) * step(p.x, -.66));
            specAmt = .18; gloss = 20.;
        } else if (m < 7.5) {
            alb = float3(.26,.37,.22); specAmt = .12;
        } else if (m < 8.5) {
            alb = float3(.99,.99,.97); specAmt = .25; gloss = 30.;
            float3 q = toSign(p);
            if (q.y < -.2 && q.z > 0.) {
                float2 u = q.xy - float2(0., -.47);
                float3 ink = mix(float3(.16,.33,.85), float3(.75,.12,.09), step(.5, uFail));
                alb = mix(alb, ink, smoothstep(.006, -.006, glyph(u)));
                alb = mix(alb, float3(.86,.88,.84), smoothstep(.006, .0, abs(sdBox(float3(u,0.), float3(.19,.165,1.), .055)) - .004));
            }
        } else if (m < 9.5) {
            alb = float3(.30,.18,.07); specAmt = .15;
        } else if (m < 10.5) {
            // rope: twisted strands
            alb = mix(float3(.80,.66,.42), float3(.60,.46,.26), smoothstep(-.3, .3, sin((p.y + abs(p.x)*.9)*95.)));
            specAmt = .05;
        } else {
            // wooden bar, with a little grain
            alb = mix(float3(.58,.36,.17), float3(.46,.27,.11), smoothstep(-.4, .4, sin(p.x*60. + sin(p.z*40.)*1.5)));
            specAmt = .3; gloss = 30.;
        }
    }

    // fragCoord is GLSL's gl_FragCoord.xy: origin at the bottom left.
    float4 pixel(float2 fragCoord) {
        // 3.4 x 3.3 units of world. The swing's ropes start at the top centre of the page, which is the pivot.
        float2 uv = fragCoord / un.uRes;
        float3 ro = float3((uv.x - .5)*3.4, -(1. - uv.y)*3.3, 3.);
        float3 rd = float3(0., 0., -1.);

        float t = 0., minD = 1e3, m = 0., tN = 0., mN = 0.; bool hit = false;
        for (int i = 0; i < 80; i++) {
            float2 h = map(ro + rd*t);
            if (h.x < minD) { minD = h.x; tN = t; mN = h.y; }
            if (h.x < .0012) { hit = true; m = h.y; break; }
            t += h.x * .92;
            if (t > 6.) break;
        }
        if (!hit) {
            // stray hairs just past the outline of the fur
            if (mN < 1.5 && minD < .04) {
                float3 pn = ro + rd*tN; float3 nn = calcN(pn);
                float fa = 1. - minD/.04; fa = fa*fa*smoothstep(.4, .8, fur(pn));
                float3 alb; float g, s; shade(pn, nn, mN, alb, g, s);
                float3 Lh = normalize(float3(-.48, .78, .62));
                float3 col = pow(alb, float3(2.2)) * (float3(.30) + float3(1.,.95,.86)*clamp((dot(nn, Lh) + .32)/1.32, 0., 1.)*1.1);
                col = pow(col, float3(.4545));
                return float4(col*fa, fa);
            }
            return float4(0.);
        }
        float3 p = ro + rd*t;
        float3 n0 = calcN(p), n = n0;
        float3 alb; float gloss, specAmt;
        shade(p, n, m, alb, gloss, specAmt);
        float fz = 1.;
        if (m < 1.5) {
            float f = fur(p);
            alb *= mix(.80, 1.10, f);                                                   // light and dark strands
            n = normalize(n + .28*float3(f - .5, 0., fur(p + float3(.013)) - .5));      // each strand catches the light a little differently
            float graze = 1. - max(dot(n0, float3(0.,0.,1.)), 0.);
            fz = mix(1., smoothstep(.3, .75, f), smoothstep(.6, .95, graze));           // a broken, fuzzy outline
        }
        alb = pow(alb, float3(2.2));

        float3 L = normalize(float3(-.48, .78, .62));
        float3 V = float3(0., 0., 1.);
        float wrap = clamp((dot(n, L) + .32)/1.32, 0., 1.);
        float sh = mix(.38, 1., shadow(p + n*.012, L));
        float occ = ao(p, n);
        float3 sky = mix(float3(.42,.30,.22), float3(.62,.70,.86), n.y*.5 + .5);       // warm bounce below, cool sky above
        float3 col = alb * (sky*.42*occ + float3(1.,.95,.86)*wrap*sh*1.25);
        float3 H = normalize(L + V);
        col += specAmt * .6 * pow(max(dot(n, H), 0.), gloss) * sh * float3(1.,.97,.9);
        float fres = pow(1. - max(dot(n, V), 0.), 3.);
        col += fres * (.10 + .16*max(n.y, 0.)) * mix(alb, float3(1.,.95,.85), .5) * occ;   // rim light
        col = pow(col, float3(.4545));
        // edge antialiasing from how grazing the surface is
        float a = smoothstep(0., .22, dot(n0, V) + .04) * fz;
        return float4(col*a, a);
    }
};

fragment float4 snuffler_fragment(VOut in [[stage_in]], constant Uniforms &uniforms [[buffer(0)]]) {
    Snuffler s; s.un = uniforms;
    // The one Y flip: Metal's pixel origin is the top left, gl_FragCoord's is the bottom left.
    return s.pixel(float2(in.position.x, uniforms.uRes.y - in.position.y));
}

// ---------- pass 2: drop shadow ----------
// Must match CompositeUniforms in Swift.
struct CompositeUniforms {
    float2 res;      // size of the target, in pixels
    float2 offset;   // the shadow's offset, in pixels (y down)
    float sigma;     // the blur's standard deviation, in pixels. 0 = no shadow, pass 1 unchanged
    float lod;       // which mip level of pass 1 to blur from
};

fragment float4 composite_fragment(VOut in [[stage_in]],
                                   constant CompositeUniforms &c [[buffer(0)]],
                                   texture2d<float> scene [[texture(0)]],
                                   sampler smp [[sampler(0)]]) {
    float4 src = scene.sample(smp, in.position.xy / c.res, level(0.));
    if (c.sigma <= 0. || src.a > .999) return src;
    // A Gaussian blur of his alpha, 11 x 11 taps. The taps read a mip level whose texels are about
    // half a sigma wide, so the cost doesn't grow with his size. The mip's own softening is taken off sigma.
    float spacing = c.sigma * .5;
    float inv2s2 = 1. / (2. * c.sigma * c.sigma * (1. - 1./16.));
    float texel = exp2(c.lod);
    float sum = 0., wsum = 0.;
    for (int j = -5; j <= 5; j++) {
        for (int i = -5; i <= 5; i++) {
            float2 d = float2(float(i), float(j)) * spacing;
            float w = exp(-dot(d, d) * inv2s2);
            float2 qp = in.position.xy - c.offset + d;
            // Nothing outside the page casts a shadow. The ramp is one mip texel wide, so edge texels aren't counted twice.
            float2 e = clamp(min(qp, c.res - qp) / texel + .5, 0., 1.);
            sum += w * e.x * e.y * scene.sample(smp, qp / c.res, level(c.lod)).a;
            wsum += w;
        }
    }
    float sa = .33 * sum / wsum;                          // rgba(20, 12, 4, .33)
    float4 shadowCol = float4(float3(20., 12., 4.) / 255. * sa, sa);
    return src + (1. - src.a) * shadowCol;                // premultiplied "over"
}
