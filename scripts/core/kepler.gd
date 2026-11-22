extends RefCounted
class_name Kepler

# Exact 2-Body Analytical Keplerian Orbit Solver (Vis-Viva + Newton-Raphson Kepler's Equation)
# Guarantees ZERO numerical drift over infinite revolutions with exact physical speed variation
# (genuinely faster near Periapsis Pe, slower near Apoapsis Ap).

static func compute_elements(r_vec: Vector2, v_vec: Vector2, mu: float, body_id: String, body_rad: float, atmos_r: float, soi_r: float) -> Dictionary:
	var r := r_vec.length()
	if r < 10.0 or mu <= 1.0:
		return {"valid": false, "closed": false}
	var v2 := v_vec.length_squared()
	var h := r_vec.x * v_vec.y - r_vec.y * v_vec.x
	var dir_sign := 1.0 if h >= 0.0 else -1.0
	var eps := 0.5 * v2 - mu / r
	var e_vec := ((v2 - mu / r) * r_vec - r_vec.dot(v_vec) * v_vec) / mu
	var e := e_vec.length()
	var omega := e_vec.angle() if e > 1e-5 else r_vec.angle()

	if eps < -1e-4 and e < 0.992 and absf(h) > 10.0:
		var a := -mu / (2.0 * eps)
		var rp := a * (1.0 - e)
		var ra := a * (1.0 + e)
		if a > 10.0 and a < 5e7:
			var n := sqrt(mu / (a * a * a))
			var nu := wrapf((r_vec.angle() - omega) * dir_sign, -PI, PI)
			var sq_m := sqrt(maxf(0.0, 1.0 - e))
			var sq_p := sqrt(1.0 + e)
			var E := 2.0 * atan2(sq_m * sin(nu * 0.5), sq_p * cos(nu * 0.5))
			var M := wrapf(E - e * sin(E), -PI, PI)
			var safe_r := maxf(body_rad + 32.0, atmos_r + 12.0)
			var status := "stable"
			if rp <= body_rad + 24.0:
				status = "impact"
			elif atmos_r > body_rad and rp <= atmos_r + 8.0:
				status = "aero"
			elif ra >= soi_r * 0.98:
				status = "escape_soi"
			var c_om := cos(omega)
			var s_om := sin(omega)
			var pe_rel := Vector2(c_om, s_om) * rp
			var ap_rel := Vector2(-c_om, -s_om) * ra
			return {
				"valid": true, "closed": true, "body_id": body_id, "mu": mu,
				"a": a, "e": e, "omega": omega, "dir_sign": dir_sign,
				"n": n, "M": M, "E": E, "rp": rp, "ra": ra,
				"period": TAU / maxf(1e-6, n), "status": status,
				"can_lock": (rp > safe_r and ra < soi_r * 0.97),
				"pe_rel": pe_rel, "ap_rel": ap_rel,
			}

	return {
		"valid": true, "closed": false, "body_id": body_id, "mu": mu,
		"e": e, "omega": omega, "dir_sign": dir_sign,
		"status": "escape" if eps >= 0.0 else "suborbital",
		"can_lock": false,
	}

static func solve_eccentric_anomaly(M: float, e: float) -> float:
	var m_w := wrapf(M, -PI, PI)
	var E := m_w + e * sin(m_w)
	if e > 0.8:
		E = PI if m_w >= 0.0 else -PI
	for _i in range(8):
		var f := E - e * sin(E) - m_w
		var df := 1.0 - e * cos(E)
		var step := f / maxf(1e-6, df)
		E -= step
		if absf(step) < 1e-7:
			break
	return E

static func eval_state(orb: Dictionary, M_val: float) -> Dictionary:
	var a := float(orb["a"])
	var e := float(orb["e"])
	var omega := float(orb["omega"])
	var dir_sign := float(orb["dir_sign"])
	var mu := float(orb["mu"])

	var E := solve_eccentric_anomaly(M_val, e)
	var cosE := cos(E)
	var sinE := sin(E)
	var b_fac := sqrt(maxf(0.0, 1.0 - e * e))

	var px := a * (cosE - e)
	var py := dir_sign * a * b_fac * sinE
	var r_mag := maxf(1.0, a * (1.0 - e * cosE))
	var k := sqrt(mu * a) / r_mag
	var vx := -sinE * k
	var vy := dir_sign * b_fac * cosE * k

	var c_om := cos(omega)
	var s_om := sin(omega)
	var pos_rel := Vector2(c_om * px - s_om * py, s_om * px + c_om * py)
	var vel_rel := Vector2(c_om * vx - s_om * vy, s_om * vx + c_om * vy)
	return {"pos_rel": pos_rel, "vel_rel": vel_rel, "E": E, "r": r_mag}

static func sample_ellipse(orb: Dictionary, body_pos: Vector2, segs: int = 96) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not bool(orb.get("closed", false)):
		return pts
	var a := float(orb["a"])
	var e := float(orb["e"])
	var omega := float(orb["omega"])
	var dir_sign := float(orb["dir_sign"])
	var b_fac := sqrt(maxf(0.0, 1.0 - e * e))
	var c_om := cos(omega)
	var s_om := sin(omega)
	pts.resize(segs + 1)
	for i in range(segs + 1):
		var E := float(i) / float(segs) * TAU
		var px := a * (cos(E) - e)
		var py := dir_sign * a * b_fac * sin(E)
		pts[i] = body_pos + Vector2(c_om * px - s_om * py, s_om * px + c_om * py)
	return pts

static func predict_open_arc(r_vec: Vector2, v_vec: Vector2, mu: float, body_pos: Vector2, body_rad: float, soi_r: float, steps: int = 80, dt: float = 0.65) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p := r_vec
	var v := v_vec
	pts.append(body_pos + p)
	for _i in range(steps):
		var r := p.length()
		if r <= body_rad + 14.0 or r >= soi_r * 1.05:
			break
		# Symplectic Velocity Verlet step
		var a0 := (-p / r) * (mu / (r * r))
		var p_next := p + v * dt + a0 * (0.5 * dt * dt)
		var r1 := maxf(10.0, p_next.length())
		var a1 := (-p_next / r1) * (mu / (r1 * r1))
		v += (a0 + a1) * (0.5 * dt)
		p = p_next
		pts.append(body_pos + p)
	return pts
