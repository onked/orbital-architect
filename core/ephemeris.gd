class_name Ephemeris
extends RefCounted

const AU_M := 149597870700.0
const DEG := PI / 180.0
const CENTURY_S := 3155760000.0

static func solve_kepler(mean_anomaly_rad: float, e: float) -> float:
	var E: float = mean_anomaly_rad + e * sin(mean_anomaly_rad)
	for _i in range(16):
		var delta: float = (E - e * sin(E) - mean_anomaly_rad) / (1.0 - e * cos(E))
		E -= delta
		if absf(delta) < 1.0e-12:
			break
	return E

static func state_xy(a_m: float, e: float, i_deg: float, L_deg: float,
		peri_deg: float, node_deg: float, mu: float, mean_motion: float = 0.0,
		omega_dot: float = 0.0, node_dot: float = 0.0, inc_dot: float = 0.0) -> PackedFloat64Array:
	var inc: float = i_deg * DEG
	var node: float = node_deg * DEG
	var omega: float = (peri_deg - node_deg) * DEG
	var M: float = fposmod(L_deg - peri_deg, 360.0) * DEG
	if M > PI:
		M -= TAU

	var E: float = solve_kepler(M, e)
	var cos_e: float = cos(E)
	var sin_e: float = sin(E)
	var sqrt_term: float = sqrt(maxf(1.0 - e * e, 0.0))

	var xp: float = a_m * (cos_e - e)
	var yp: float = a_m * sqrt_term * sin_e

	var n: float = mean_motion
	if n <= 0.0:
		n = sqrt(mu / (a_m * a_m * a_m))
	var e_dot: float = n / maxf(1.0 - e * cos_e, 1.0e-9)
	var vxp: float = -a_m * sin_e * e_dot
	var vyp: float = a_m * sqrt_term * cos_e * e_dot

	var cw: float = cos(omega)
	var sw: float = sin(omega)
	var cn: float = cos(node)
	var sn: float = sin(node)
	var ci: float = cos(inc)
	var si: float = sin(inc)

	var m00: float = cw * cn - sw * sn * ci
	var m01: float = -sw * cn - cw * sn * ci
	var m10: float = cw * sn + sw * cn * ci
	var m11: float = -sw * sn + cw * cn * ci

	var out := PackedFloat64Array()
	out.resize(4)
	out[0] = m00 * xp + m01 * yp
	out[1] = m10 * xp + m11 * yp
	if omega_dot == 0.0 and node_dot == 0.0 and inc_dot == 0.0:
		out[2] = m00 * vxp + m01 * vyp
		out[3] = m10 * vxp + m11 * vyp
		return out

	var d00w: float = -sw * cn - cw * sn * ci
	var d00n: float = -cw * sn - sw * cn * ci
	var d00i: float = sw * sn * si
	var d01w: float = -cw * cn + sw * sn * ci
	var d01n: float = sw * sn - cw * cn * ci
	var d01i: float = cw * sn * si
	var d10w: float = -sw * sn + cw * cn * ci
	var d10n: float = cw * cn - sw * sn * ci
	var d10i: float = -sw * cn * si
	var d11w: float = -cw * sn - sw * cn * ci
	var d11n: float = -sw * cn + cw * sn * ci
	var d11i: float = -cw * cn * si
	var dm00: float = d00w * omega_dot + d00n * node_dot + d00i * inc_dot
	var dm01: float = d01w * omega_dot + d01n * node_dot + d01i * inc_dot
	var dm10: float = d10w * omega_dot + d10n * node_dot + d10i * inc_dot
	var dm11: float = d11w * omega_dot + d11n * node_dot + d11i * inc_dot
	out[2] = m00 * vxp + m01 * vyp + dm00 * xp + dm01 * yp
	out[3] = m10 * vxp + m11 * vyp + dm10 * xp + dm11 * yp
	return out

static func state_from_elements(a_m: float, e: float, i_deg: float, L_deg: float,
		peri_deg: float, node_deg: float, mu: float) -> Dictionary:
	var s: PackedFloat64Array = state_xy(a_m, e, i_deg, L_deg, peri_deg, node_deg, mu)
	return {"pos": Vector2(s[0], s[1]), "vel": Vector2(s[2], s[3])}
