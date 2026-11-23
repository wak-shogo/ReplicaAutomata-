shader_type canvas_item;
render_mode blend_mix, unshaded;

// Fully Ray-Traced Physical Sunlight, Per-Voxel Terrain/Cave Shadows,
// Mutual Planetary Eclipses, Atmospheric Spectral Tint, & Dynamic Emissive Point Lights.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Real-time polar voxel occupancy textures (R = 1.0 solid rock, 0.0 open air/cave)
uniform sampler2D u_terra_occ : filter_nearest, repeat_enable;
uniform sampler2D u_extra_occ : filter_nearest, repeat_enable;

uniform vec2 u_cam_pos = vec2(0.0, 0.0);
uniform float u_cam_zoom = 1.0;
uniform vec2 u_vp_size = vec2(1280.0, 720.0);
uniform float u_time = 0.0;
uniform float u_sun_rad = 2200.0;

// 5 celestial bodies: 0=terra, 1=luna, 2=ignis, 3=cryo, 4=astra
// xy = world_pos, z = r_surface, w = r_atmos_visual
uniform vec4 u_body_geom[5];
// x = r_core, y = cell_h, z = occ_band_idx (-1 for terra, 0..3 for extra), w = core_glow_strength
uniform vec4 u_body_vox[5];
// xyz = core glow color, w = unused
uniform vec4 u_body_core_col[5];
// xyz = Rayleigh beta_R, w = H_R ratio
uniform vec4 u_body_rayleigh[5];
// xyz = Mie beta_M tint, w = H_M ratio
uniform vec4 u_body_mie[5];

// Dynamic point lights: xy = world_pos, z = radius, w = intensity
uniform int u_light_count = 0;
uniform vec4 u_light_pos_rad[32];
// xyz = rgb color, w = unused
uniform vec4 u_light_col[32];

const float PI_C = 3.14159265359;
const float TAU_C = 6.28318530718;

float sample_voxel_occ(int bidx, vec2 rel_p) {
	float r = length(rel_p);
	float r_core = u_body_vox[bidx].x;
	float r_surf = u_body_geom[bidx].z;
	if (r <= r_core + 4.0) {
		return 1.0;
	}
	if (r >= r_surf) {
		return 0.0;
	}
	float a = atan(rel_p.y, rel_p.x);
	if (a < 0.0) {
		a += TAU_C;
	}
	float u = fract(a / TAU_C);
	float v_row = clamp((r - r_core) / max(1.0, r_surf - r_core), 0.0, 0.998);
	if (bidx == 0) {
		return texture(u_terra_occ, vec2(u, v_row)).r;
	}
	float band = u_body_vox[bidx].z;
	float v_pack = (band + v_row) * 0.25;
	return texture(u_extra_occ, vec2(u, v_pack)).r;
}

float ray_circle_exit(vec2 ro, vec2 rd, vec2 center, float rad) {
	vec2 oc = ro - center;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - rad * rad;
	float disc = b * b - c;
	if (disc <= 0.0) {
		return 0.0;
	}
	return max(0.0, -b + sqrt(disc));
}

// Compute physical Beer-Lambert spectral sunlight transmittance through planet's atmosphere
vec3 atmos_transmittance(int bidx, vec2 p, vec2 sun_dir) {
	float r_atmos = u_body_geom[bidx].w;
	if (r_atmos <= 1.0) {
		return vec3(1.0);
	}
	vec2 b_pos = u_body_geom[bidx].xy;
	float r_surf = u_body_geom[bidx].z;
	float thick = max(1.0, r_atmos - r_surf);
	float H_R = thick * u_body_rayleigh[bidx].w;
	float H_M = thick * u_body_mie[bidx].w;

	float t_exit = ray_circle_exit(p, sun_dir, b_pos, r_atmos);
	if (t_exit <= 0.0) {
		return vec3(1.0);
	}
	const int ASTEPS = 8;
	float dt = t_exit / float(ASTEPS);
	float opt_R = 0.0;
	float opt_M = 0.0;
	for (int s = 0; s < ASTEPS; s++) {
		vec2 q = p + sun_dir * ((float(s) + 0.5) * dt);
		float hq = max(0.0, length(q - b_pos) - r_surf);
		opt_R += exp(-hq / max(1.0, H_R)) * dt;
		opt_M += exp(-hq / max(1.0, H_M)) * dt;
	}
	vec3 beta_R = u_body_rayleigh[bidx].xyz;
	vec3 beta_M_c = u_body_mie[bidx].xyz;
	float beta_M = max(beta_M_c.r, max(beta_M_c.g, beta_M_c.b));
	return exp(-(beta_R * opt_R + vec3(beta_M * 1.15) * opt_M));
}

// Ray-trace sunlight from world pixel p toward Sun (0,0) through actual carved voxel terrain!
float trace_voxel_sunlight(int bidx, vec2 p, vec2 sun_dir) {
	vec2 b_pos = u_body_geom[bidx].xy;
	float r_surf = u_body_geom[bidx].z;
	float r_core = u_body_vox[bidx].x;
	vec2 rel = p - b_pos;
	float r = length(rel);
	vec2 up_n = rel / max(1.0, r);

	// 1. Check analytic core intersection along ray to Sun
	vec2 to_c = -rel;
	float proj = dot(to_c, sun_dir);
	if (proj > 0.0) {
		float d_perp = length(to_c - sun_dir * proj);
		if (d_perp < r_core * 0.96) {
			return 0.0;
		}
	}

	// 2. If inside or near the planet crust, raymarch the real polar voxel grid toward the Sun!
	// Offset slightly along sun_dir + slight outward bias if currently on surface edge so
	// buildings/surface regolith facing the Sun aren't self-shadowed by their own pixel.
	float start_bias = (r >= r_surf - 36.0) ? 28.0 : 18.0;
	vec2 q = rel + sun_dir * start_bias + up_n * ((r >= r_surf - 36.0) ? 14.0 : 0.0);

	// Exit distance to outer terrain shell (r_surf + 20)
	float t_max = ray_circle_exit(b_pos + q, sun_dir, b_pos, r_surf + 24.0);
	if (t_max <= 1.0) {
		return 1.0;
	}

	float occ_sum = 0.0;
	float t = 0.0;
	const int STEPS = 28;
	for (int s = 0; s < STEPS; s++) {
		// Adaptive step: fine near pixel (catches cave shafts & cliff edges), wider farther out
		float frac = float(s) / float(STEPS - 1);
		float step_d = mix(18.0, max(58.0, t_max / 10.0), frac * frac);
		t += step_d;
		if (t > t_max) {
			break;
		}
		vec2 qp = q + sun_dir * t;
		float qr = length(qp);
		if (qr > r_surf) {
			if (dot(qp, sun_dir) > 0.0) {
				break;
			}
			continue;
		}
		if (qr < r_core) {
			return 0.0;
		}
		float solid = sample_voxel_occ(bidx, qp);
		if (solid > 0.5) {
			// Accumulate smooth optical rock thickness for soft penumbra shafts into caves
			occ_sum += step_d * 0.0115;
			if (occ_sum >= 1.0) {
				return 0.0;
			}
		}
	}
	return clamp(1.0 - occ_sum, 0.0, 1.0);
}

void fragment() {
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	vec2 p = u_cam_pos + (UV - vec2(0.5)) * (u_vp_size / max(0.005, u_cam_zoom));

	float d_sun = length(p);
	vec2 sun_dir = -p / max(1.0, d_sun);

	// Never darken the Sun itself!
	if (d_sun < u_sun_rad * 1.18) {
		COLOR = vec4(base, 1.0);
	} else {
		// Find closest / containing planet body
		int dom_idx = -1;
		float dom_dist = 1e9;
		for (int i = 0; i < 5; i++) {
			float d = length(p - u_body_geom[i].xy);
			float bound = max(u_body_geom[i].z + 320.0, u_body_geom[i].w + 200.0);
			if (d < bound && d < dom_dist) {
				dom_dist = d;
				dom_idx = i;
			}
		}

		// 1. Mutual planetary / lunar eclipse shadow check across ALL other bodies
		float eclipse_vis = 1.0;
		for (int k = 0; k < 5; k++) {
			if (k == dom_idx) {
				continue;
			}
			vec2 c = u_body_geom[k].xy;
			float rad = u_body_geom[k].z;
			vec2 to_c = c - p;
			float proj = dot(to_c, sun_dir);
			if (proj > 0.0 && proj < d_sun) {
				float d_perp = length(to_c - sun_dir * proj);
				float pen = max(65.0, u_sun_rad * (proj / max(1.0, d_sun)));
				eclipse_vis *= smoothstep(rad * 0.96 - pen * 0.45, rad * 0.99 + pen * 0.55, d_perp);
			}
		}

		// 2. If in open interplanetary space (outside all planet/atmos bounds), apply subtle space lighting & point lights
		if (dom_idx < 0) {
			vec3 space_lit = base * mix(0.28, 1.04, eclipse_vis);
			vec3 pt_add = vec3(0.0);
			for (int li = 0; li < 32; li++) {
				if (li >= u_light_count) {
					break;
				}
				vec2 lp = u_light_pos_rad[li].xy;
				float lrad = u_light_pos_rad[li].z;
				float lint = u_light_pos_rad[li].w;
				float ld = length(p - lp);
				if (ld < lrad) {
					float att = pow(1.0 - ld / lrad, 2.0) * lint;
					pt_add += u_light_col[li].rgb * att;
				}
			}
			COLOR = vec4(clamp(space_lit + base * pt_add * 0.85 + pt_add * 0.08, 0.0, 1.0), 1.0);
		} else {
			// 3. Inside or near a Planet: Full Voxel Ray-Traced Sunlight + Atmospheric Spectral Tint + Core Glow!
			vec2 b_pos = u_body_geom[dom_idx].xy;
			float r_surf = u_body_geom[dom_idx].z;
			float r_atmos = u_body_geom[dom_idx].w;
			float r_core = u_body_vox[dom_idx].x;
			vec2 rel = p - b_pos;
			float r = length(rel);
			vec2 up_n = rel / max(1.0, r);
			float sun_dot = dot(up_n, sun_dir);

			// Preserve blazing molten planetary core brightness (emissive!)
			float core_emissive = 1.0 - smoothstep(r_core * 0.92, r_core * 1.12, r);

			// Check whether pixel is inside the planet's terrain zone vs open sky above surface
			float in_planet_zone = 1.0 - smoothstep(r_surf + 12.0, r_surf + 145.0, r);

			// Real ray-traced voxel sunlight (traces through actual hills, craters, dug caves, and planet curvature!)
			float sun_vis = 1.0;
			if (r < r_surf + 150.0) {
				sun_vis = trace_voxel_sunlight(dom_idx, p, sun_dir);
				float horizon_soft = smoothstep(-0.18, 0.24, sun_dot);
				float surf_mix = smoothstep(r_surf - 140.0, r_surf - 10.0, r);
				sun_vis *= mix(1.0, horizon_soft, surf_mix * 0.72);
			} else {
				vec2 to_c = -rel;
				float proj = dot(to_c, sun_dir);
				if (proj > 0.0) {
					float d_perp = length(to_c - sun_dir * proj);
					float pen = max(48.0, u_sun_rad * (proj / max(1.0, d_sun)));
					sun_vis = smoothstep(r_surf * 0.97 - pen * 0.4, r_surf * 1.00 + pen * 0.5, d_perp);
				}
			}
			sun_vis *= eclipse_vis;

			// Beer-Lambert spectral sunlight color (radiant white-gold at noon -> rich sunset amber-crimson at twilight!)
			vec3 T_sun = atmos_transmittance(dom_idx, p, sun_dir);
			vec3 direct_sun_col = mix(vec3(1.04, 1.01, 0.97), T_sun * 1.38, (r_atmos > 1.0) ? 0.92 : 0.0);

			// Sky bounce ambient (cool azure on dayside, warm twilight bounce near terminator, deep starry indigo at night)
			float depth_norm = clamp((r_surf - r) / max(1.0, r_surf - r_core), 0.0, 1.0);
			float sky_reach = exp(-depth_norm * 5.2);
			vec3 day_sky_amb = (r_atmos > 1.0) ? vec3(0.24, 0.36, 0.54) : vec3(0.14, 0.16, 0.22);
			vec3 twi_sky_amb = (r_atmos > 1.0) ? (T_sun * vec3(0.42, 0.26, 0.20)) : vec3(0.08, 0.09, 0.12);
			vec3 night_amb = vec3(0.11, 0.14, 0.22);
			float day_w = smoothstep(-0.22, 0.35, sun_dot) * eclipse_vis;
			float twi_w = smoothstep(-0.35, 0.02, sun_dot) * (1.0 - smoothstep(0.02, 0.45, sun_dot)) * eclipse_vis;
			vec3 sky_amb = mix(night_amb, day_sky_amb, day_w) + twi_sky_amb * twi_w * 0.65;

			// Deep underground ambient (subtle cool cavern bounce so cave structure remains readable)
			vec3 cave_floor_amb = vec3(0.13, 0.15, 0.22);
			vec3 ambient_col = mix(cave_floor_amb, sky_amb, sky_reach);

			// Planetary molten / exotic core radiance illuminating deep underground chambers
			float core_dist = max(0.0, r - r_core);
			float core_falloff = exp(-core_dist / max(120.0, (r_surf - r_core) * 0.26));
			vec3 core_light = u_body_core_col[dom_idx].rgb * core_falloff * u_body_vox[dom_idx].w;

			// Dynamic point lights (Player headlamp auto-dims in bright daylight so sand never washes out!)
			vec3 dyn_light = vec3(0.0);
			vec3 dyn_glow = vec3(0.0);
			float day_dim = mix(1.0, 0.14, clamp(sun_vis * day_w, 0.0, 1.0));
			for (int li = 0; li < 32; li++) {
				if (li >= u_light_count) {
					break;
				}
				vec2 lp = u_light_pos_rad[li].xy;
				float lrad = u_light_pos_rad[li].z;
				float lint = u_light_pos_rad[li].w * ((li == 0) ? day_dim : 1.0);
				float ld = length(p - lp);
				if (ld < lrad) {
					float qn = 1.0 - ld / lrad;
					float att = qn * qn * lint;
					dyn_light += u_light_col[li].rgb * att;
					dyn_glow += u_light_col[li].rgb * (qn * qn * qn) * lint * 0.08;
				}
			}

			// Emissive pixel preservation (keep bright glowing ore crystals, lasers, HUD indicators, magma & plasma crisp!)
			float base_max = max(base.r, max(base.g, base.b));
			float base_min = min(base.r, min(base.g, base.b));
			float sat = (base_max > 0.01) ? ((base_max - base_min) / base_max) : 0.0;
			float self_emissive = smoothstep(0.68, 0.96, base_max) * smoothstep(0.32, 0.78, sat) * 0.58;

			// Combine traced direct sunlight + sky/cave ambient + planetary core light + dynamic point lights
			vec3 raw_light = ambient_col + direct_sun_col * sun_vis * 0.92 + core_light + dyn_light;
			// Soft filmic shoulder prevents over-exposure clipping on bright sunlit regolith!
			vec3 total_light = raw_light / (vec3(1.0) + raw_light * 0.24);

			float sky_preserve = 1.0 - in_planet_zone;
			vec3 planet_lit = base * mix(total_light, vec3(1.0), clamp(core_emissive + self_emissive, 0.0, 0.90)) + dyn_glow;
			vec3 air_lit = base * mix(vec3(0.94, 0.96, 1.0), vec3(1.02, 1.01, 0.99), sun_vis) + dyn_glow * 0.65;

			vec3 final_col = mix(planet_lit, air_lit, sky_preserve);

			// Subtle physical foreground atmospheric aerial haze near sunlit planetary horizon!
			if (r_atmos > 1.0 && r < r_atmos) {
				float thick = max(1.0, r_atmos - r_surf);
				float h = max(0.0, r - r_surf);
				float rho = exp(-h / (thick * 0.28)) * smoothstep(r_atmos, r_surf + thick * 0.6, r);
				float limb_band = smoothstep(r_surf - 80.0, r_surf + 30.0, r) * (1.0 - smoothstep(r_surf + 40.0, r_atmos, r));
				vec3 haze_col = mix(u_body_rayleigh[dom_idx].xyz * 420.0, T_sun * vec3(1.10, 0.62, 0.34), twi_w);
				float haze_amt = (0.032 * rho * day_w + 0.085 * limb_band * (day_w * 0.55 + twi_w * 1.15)) * eclipse_vis;
				final_col += haze_col * clamp(haze_amt, 0.0, 0.16);
			}

			COLOR = vec4(clamp(final_col, 0.0, 1.0), 1.0);
		}
	}
}
