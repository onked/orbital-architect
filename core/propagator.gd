class_name Propagator
extends RefCounted

static func rk4_step(state: CraftState, universe: Universe, t: float, dt: float) -> void:
	var p0x: float = state.px
	var p0y: float = state.py
	var v0x: float = state.vx
	var v0y: float = state.vy

	var a1: Vector2 = universe.accel_xy(p0x, p0y, t)

	var vmx: float = v0x + a1.x * (dt * 0.5)
	var vmy: float = v0y + a1.y * (dt * 0.5)
	var pmx: float = p0x + v0x * (dt * 0.5)
	var pmy: float = p0y + v0y * (dt * 0.5)
	var a2: Vector2 = universe.accel_xy(pmx, pmy, t + dt * 0.5)

	var vvx: float = v0x + a2.x * (dt * 0.5)
	var vvy: float = v0y + a2.y * (dt * 0.5)
	var ppx: float = p0x + vmx * (dt * 0.5)
	var ppy: float = p0y + vmy * (dt * 0.5)
	var a3: Vector2 = universe.accel_xy(ppx, ppy, t + dt * 0.5)

	var vex: float = v0x + a3.x * dt
	var vey: float = v0y + a3.y * dt
	var pex: float = p0x + vvx * dt
	var pey: float = p0y + vvy * dt
	var a4: Vector2 = universe.accel_xy(pex, pey, t + dt)

	state.px = p0x + (v0x + 2.0 * vmx + 2.0 * vvx + vex) * (dt / 6.0)
	state.py = p0y + (v0y + 2.0 * vmy + 2.0 * vvy + vey) * (dt / 6.0)
	state.vx = v0x + (a1.x + 2.0 * a2.x + 2.0 * a3.x + a4.x) * (dt / 6.0)
	state.vy = v0y + (a1.y + 2.0 * a2.y + 2.0 * a3.y + a4.y) * (dt / 6.0)
