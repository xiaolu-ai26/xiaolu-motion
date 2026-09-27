/* ==========================================================================
   xiaolu-motion · engine/particles.js
   Deterministic particles (pure functions of time + seed, no state):
   - sparks(): short-lived streaks thrown sideways from a cut point
     (from 《在我开口之前》 s23.js blade sparks)
   - dust(): slow drifting motes with twinkle (from s910.js dust / poster.js)
   Both draw the crisp particle into ctx and a soft halo into glow (if given).
   ========================================================================== */
import { TAU, clamp, hash2, mixHex, softDot, drawSprite, Noise } from './core.js';

/* burst of streak sparks emitted at t = 0 (tau = time since the cut).
   o: {x, y, seed, count, spreadY (px vertical spread of emitters), speed [min,max] px/s,
       life [min,max] s, gravity px/s^2, colorHot, colorCool, glowColor, width, s (scale)} */
export function sparks(ctx, glow, tau, o) {
  if (tau < 0) return;
  const n = o.count ?? 9, s = o.s ?? 1;
  const sp = o.speed || [240, 700], lf = o.life || [0.28, 0.52];
  for (let i = 0; i < n; i++) {
    const h1 = hash2(o.seed * 31 + 7, i), h2 = hash2(o.seed * 31 + 11, i), h3 = hash2(o.seed * 31 + 13, i), h4 = hash2(o.seed * 31 + 17, i);
    const life = lf[0] + (lf[1] - lf[0]) * h3;
    if (tau > life) continue;
    const side = (o.dir ?? 0) !== 0 ? Math.sign(o.dir) : (i % 2 ? 1 : -1);
    const vx = side * (sp[0] + (sp[1] - sp[0]) * h1) * s, vy = (h2 - 0.5) * 420 * s;
    const td = 0.14, kk = 1 - Math.exp(-tau / td);
    const ox = o.x, oy = o.y + (h4 - 0.5) * (o.spreadY ?? 130) * s;
    const px = ox + vx * td * kk, py = oy + vy * td * kk + (o.gravity ?? 160) * s * tau * tau;
    const spd = Math.exp(-tau / td);
    const lx = vx * spd * 0.022, ly = vy * spd * 0.022;
    const a = Math.pow(1 - tau / life, 1.6);
    if (ctx) {
      ctx.strokeStyle = mixHex(o.colorHot || '#ffffff', o.colorCool || o.colorHot || '#ffffff', tau / life, a);
      ctx.lineWidth = (o.width ?? 1.5) * s; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(px - lx - side, py - ly); ctx.lineTo(px, py); ctx.stroke();
    }
    if (glow) drawSprite(glow, softDot('c', o.glowColor || o.colorCool || '#ffffff'), px, py, 6 * s, a * 0.8);
  }
}

/* drifting dust motes over a rect. o: {x, y, w, h, count, seed, color, glowColor, r [min,max],
   speed (px/s drift), alpha, fadeIn (0..1 multiplier)} */
export function dust(ctx, glow, t, o) {
  const n = o.count ?? 40, rr = o.r || [1.1, 3.0];
  for (let i = 0; i < n; i++) {
    const h1 = hash2(o.seed * 17 + 1, i), h2 = hash2(o.seed * 17 + 2, i), h3 = hash2(o.seed * 17 + 3, i), h4 = hash2(o.seed * 17 + 4, i);
    const vx = (h3 - 0.5) * (o.speed ?? 14), vy = -(0.3 + 0.7 * h4) * (o.speed ?? 14);
    let x = o.x + ((h1 * o.w + vx * t + Noise.n1(t * 0.3, i + o.seed) * 12) % o.w + o.w) % o.w;
    let y = o.y + ((h2 * o.h + vy * t) % o.h + o.h) % o.h;
    const tw = 0.45 + 0.55 * (0.5 + 0.5 * Math.sin(t * (1 + 3 * h3) + TAU * h4));
    const a = clamp((o.alpha ?? 0.6) * tw * (o.fadeIn ?? 1));
    if (a < 0.02) continue;
    const r = rr[0] + (rr[1] - rr[0]) * h4;
    if (ctx) drawSprite(ctx, softDot('d', o.color || '#ffffff'), x, y, r * 2.2, a * 0.9);
    if (glow) drawSprite(glow, softDot('c', o.glowColor || o.color || '#ffffff'), x, y, r * 5, a * 0.5);
  }
}
