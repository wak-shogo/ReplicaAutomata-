shader_type canvas_item;
render_mode blend_mix, unshaded;

// Physically-based 2D Rayleigh + Mie Atmospheric Scattering & Solar Corona Shader
// Computes true Beer-Lambert spectral optical depth along rays toward the Sun at (0,0)
// plus soft-penumbra planetary/lunar eclipse occlusion across all 5 orbiting worlds.

uniform float u_time = 0.0;
uniform float u_sun_rad = 2200.0;

// 5 celestial bodies: 0=terra, 1=luna, 2=ignis, 3=cryo, 4=astra
// xy = world_pos, z = r_surface, w = r_atmos_visual (0 if airless)
uniform vec4 u_body_geom[5];
// xyz = Rayleigh scattering coeff beta_R (scaled), w = scale height ratio H_R
uniform vec4 u_body_rayleigh[5];
// xyz = Mie tint * beta_M, w = Mie scale height ratio H_M
uniform vec4 u_body_mie[5];

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Ray-circle intersection returning distance to outer shell exit (t_far > 0)
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

// Soft physical umbra/penumbra eclipse factor from all 5 solid planetary bodies
float eclipse_factor(vec2 p, vec2 sun_dir, float dist_sun, int self_idx) {
	float vis = 1.0;
	for (int k = 0; k < 5; k++) {
		vec2 c = u_body_geom[k].xy;
		float rad = u_body_geom[k].z;
		vec2 to_c = c - p;
		float proj = dot(to_c, sun_dir);
		if (proj > 0.0 && proj < dist_sun) {
			float d_perp = length(to_c - sun_dir * proj);
			// Real solar disc penumbra angular spread
			float pen = max(55.0, u_sun_rad * (proj / max(1.0, dist_sun)));
			// Slightly tighter inner radius for self-planet so twilight wraps naturally around limb
			float eff_r = (k == self_idx) ? (rad * 0.992) : (rad * 0.985);
			float occ = smoothstep(eff_r - pen * 0.55, eff_r + pen * 0.65, d_perp);
			vis *= occ;
		}
	}
	return vis;
}

void fragment() {
	vec2 p = v_world_pos;
	vec3 accum_rgb = vec3(0.0);
	float accum_a = 0.0;

	// 1. Physical Sun Photosphere & Animated Solar Corona at World Origin (0, 0)
	float d_sun = length(p);
	if (d_sun < u_sun_rad * 7.5) {
		vec2 sdir_n = p / max(1.0, d_sun);
		float ang = atan(sdir_n.y, sdir_n.x);
		float r_norm = d_sun / u_sun_rad;
		if (r_norm < 1.02) {
			// Limb-darkened turbulent convective photosphere
			float mu = sqrt(max(0.0, 1.0 - min(1.0, r_norm * r_norm)));
			float gran = fbm(p * 0.0028 + vec2(u_time * 0.12, -u_time * 0.08));
			float flare = fbm(p * 0.0065 - vec2(u_time * 0.22, u_time * 0.15));
			vec3 core_c = mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.58), pow(mu, 0.45));
			core_c = mix(core_c, vec3(1.0, 0.99, 0.90), pow(mu, 1.6) * (0.78 + 0.22 * gran));
			core_c += vec3(1.0, 0.58, 0.14) * flare * 0.24 * (1.0 - mu * 0.5);
			float edge = 1.0 - smoothstep(0.97, 1.02, r_norm);
			accum_rgb += core_c * edge;
			accum_a = max(accum_a, edge);
		}
		// Radial coronal plasma streamers + inverse-square Mie aureole
		float rays = fbm(vec2(ang * 4.5 + u_time * 0.06, log(max(0.6, r_norm)) * 2.2 - u_time * 0.18));
		float rays2 = fbm(vec2(ang * 9.0 - u_time * 0.09, r_norm * 1.1));
		float corona_falloff = exp(-max(0.0, r_norm - 0.95) * 1.55) * (0.72 + 0.55 * rays + 0.25 * rays2);
		float wide_halo = 0.26 / (0.18 + pow(max(0.0, r_norm - 0.85), 1.85));
		vec3 cor_c = vec3(1.0, 0.64, 0.24) * corona_falloff * 1.15 + vec3(1.0, 0.44, 0.12) * wide_halo * 0.34;
		float outer_fade = 1.0 - smoothstep(5.0, 7.5, r_norm);
		accum_rgb += cor_c * outer_fade;
		accum_a = max(accum_a, clamp(length(cor_c * outer_fade) * 0.85, 0.0, 1.0));
	}

	// 2. Physically-Traced Rayleigh + Mie Atmospheric Scattering for Each Planet
	vec2 sun_dir = -p / max(1.0, d_sun);

	for (int i = 0; i < 5; i++) {
		float r_atmos = u_body_geom[i].w;
		if (r_atmos <= 1.0) {
			continue;
		}
		vec2 b_pos = u_body_geom[i].xy;
		float r_surf = u_body_geom[i].z;
		vec2 rel = p - b_pos;
		float r = length(rel);
		if (r > r_atmos * 1.04) {
			continue;
		}

		float thick = max(1.0, r_atmos - r_surf);
		float h = max(0.0, r - r_surf);
		float h_norm = clamp(h / thick, 0.0, 1.0);
		float shell_fade = smoothstep(1.0, 0.86, h_norm);

		float H_R = thick * u_body_rayleigh[i].w;
		float H_M = thick * u_body_mie[i].w;
		float rho_R = exp(-h / max(1.0, H_R)) * shell_fade;
		float rho_M = exp(-h / max(1.0, H_M)) * shell_fade;

		// March sun ray from p to the outer boundary of this planet's atmosphere
		float t_exit = ray_circle_exit(p, sun_dir, b_pos, r_atmos);
		const int STEPS = 10;
		float dt = t_exit / float(STEPS);
		float opt_R = 0.0;
		float opt_M = 0.0;
		for (int s = 0; s < STEPS; s++) {
			float ts = (float(s) + 0.5) * dt;
			vec2 q = p + sun_dir * ts;
			float hq = max(0.0, length(q - b_pos) - r_surf);
			opt_R += exp(-hq / max(1.0, H_R)) * dt;
			opt_M += exp(-hq / max(1.0, H_M)) * dt;
		}

		vec3 beta_R = u_body_rayleigh[i].xyz;
		vec3 beta_M_col = u_body_mie[i].xyz;
		float beta_M = max(beta_M_col.r, max(beta_M_col.g, beta_M_col.b));

		// Soft physical umbra/penumbra occlusion by planets & moons
		float occ = eclipse_factor(p, sun_dir, d_sun, i);

		// Beer-Lambert spectral transmittance along the sun ray
		// Short wavelengths (blue) attenuate faster along long tangential terminator paths,
		// naturally shifting noon azure -> golden amber -> deep sunset crimson!
		vec3 tau = beta_R * opt_R + vec3(beta_M * 1.25) * opt_M;
		vec3 T_sun = exp(-tau);

		// Physical scattering phase functions (Rayleigh + Henyey-Greenstein Mie forward scatter)
		vec2 up_n = rel / max(1.0, r);
		float sun_elev = dot(up_n, sun_dir);
		float phase_R = 0.75 * (1.0 + sun_elev * sun_elev * 0.45);
		float g = 0.72;
		float cos_mie = clamp(sun_elev, -1.0, 1.0);
		float phase_M = (1.0 - g * g) / (4.0 * 3.14159 * pow(max(0.08, 1.0 + g * g - 2.0 * g * cos_mie), 1.5));

		// Primary single-scattered sunlight + physically-continuous twilight sunset Mie/Rayleigh glow
		// Calibrated so noon sky is rich luminous cerulean-azure (not clipped white!) and terminator
		// shifts organically into molten amber-orange-crimson via Beer-Lambert spectral extinction!
		vec3 single_scat = (beta_R * rho_R * phase_R * 1.15 + beta_M_col * rho_M * (0.48 + phase_M * 1.65)) * T_sun * occ * thick * 0.36;
		// Multiple-scatter upper-atmosphere twilight wrap (golden-rose glow past geometric horizon)
		float twi_band = smoothstep(-0.46, 0.22, sun_elev) * (1.0 - smoothstep(0.18, 0.58, sun_elev));
		vec3 multi_scat = (beta_R * 0.20 + beta_M_col * 0.85) * (rho_R * 0.65 + rho_M * 0.85) * exp(-tau * 0.36) * twi_band * thick * 0.26;
		// Subtle nightside airglow in upper exosphere (oxygen/nitrogen limb emission)
		vec3 airglow = beta_R * rho_R * 0.032 * thick * (1.0 - smoothstep(-0.15, 0.25, sun_elev));

		vec3 atm_lin = single_scat + multi_scat + airglow;
		// Smooth physical exposure curve preserving vivid cerulean blue & warm amber sunset saturation
		vec3 atm_col = vec3(1.0) - exp(-atm_lin * 1.05);

		// Sky opacity: rich daytime azure hides stars cleanly; night sky stays transparent for deep starfield!
		float luma = dot(atm_col, vec3(0.299, 0.587, 0.114));
		float atm_alpha = clamp(luma * 1.55 + rho_R * occ * 0.52, 0.0, 0.96) * shell_fade;

		accum_rgb += atm_col;
		accum_a = max(accum_a, atm_alpha);
	}

	COLOR = vec4(clamp(accum_rgb, 0.0, 1.0), clamp(accum_a, 0.0, 1.0));
}
