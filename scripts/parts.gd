class_name Parts
extends RefCounted
## Part catalogue and design stats. Masses in tonnes, thrust in kN, lengths in metres.

const RADIUS := 1.25
const G0 := 9.81

const NOSES := {
	"cone": {"name": "Cone", "h": 2.8, "mass": 0.15, "cd": 0.28, "torque": 0.15},
	"capsule": {"name": "Capsule", "h": 2.4, "mass": 1.0, "cd": 0.45, "torque": 0.9},
	"none": {"name": "Flat", "h": 0.3, "mass": 0.02, "cd": 0.85, "torque": 0.0},
}

const TANKS := {
	"S": {"name": "Small", "h": 2.0, "dry": 0.2, "fuel": 1.8},
	"M": {"name": "Medium", "h": 4.0, "dry": 0.4, "fuel": 4.0},
	"L": {"name": "Large", "h": 7.0, "dry": 0.7, "fuel": 7.5},
}

const ENGINES := {
	"sparrow": {"name": "Sparrow", "thrust": 70.0, "isp_sl": 285.0, "isp_vac": 320.0, "mass": 0.4, "h": 1.3, "bell": 0.5},
	"falcon": {"name": "Falcon", "thrust": 210.0, "isp_sl": 280.0, "isp_vac": 330.0, "mass": 1.2, "h": 1.9, "bell": 0.7},
	"titan": {"name": "Titan", "thrust": 650.0, "isp_sl": 270.0, "isp_vac": 315.0, "mass": 3.2, "h": 2.6, "bell": 1.0},
}

const MOUNT_H := 0.5
const MOUNT_MASS := 0.25
const FINS_MASS := 0.2
const LEGS_MASS := 0.35
const MAX_TANKS := 8
const MAX_ENGINES := 4

const MISSIONS := [
	{"name": "Hop", "alt": 300.0, "desc": "Hop to 300 m and land back on the pad."},
	{"name": "Skyline", "alt": 3000.0, "desc": "Climb to 3 km, then stick the landing."},
	{"name": "Stratosphere", "alt": 15000.0, "desc": "Punch through 15 km and come home."},
	{"name": "Edge of Space", "alt": 50000.0, "desc": "Touch 50 km where the sky turns black."},
	{"name": "Kármán Line", "alt": 100000.0, "desc": "Reach space at 100 km. Survive re-entry. Land."},
]

static func default_design() -> Dictionary:
	return {"nose": "capsule", "tanks": ["M"], "engine": "falcon", "count": 1, "fins": true, "legs": true}

static func stats(d: Dictionary) -> Dictionary:
	var nose: Dictionary = NOSES[d.nose]
	var eng: Dictionary = ENGINES[d.engine]
	var count: int = d.count
	var dry: float = nose.mass + eng.mass * count + MOUNT_MASS
	var fuel := 0.0
	var h: float = nose.h + MOUNT_H + eng.h
	for t in d.tanks:
		dry += TANKS[t].dry
		fuel += TANKS[t].fuel
		h += TANKS[t].h
	if d.fins:
		dry += FINS_MASS
	if d.legs:
		dry += LEGS_MASS
	var wet := dry + fuel
	var thrust: float = eng.thrust * count
	return {
		"dry": dry,
		"fuel": fuel,
		"wet": wet,
		"thrust": thrust,
		"isp_sl": eng.isp_sl,
		"isp_vac": eng.isp_vac,
		"height": h,
		"cd": nose.cd,
		"torque": nose.torque,
		"twr": thrust / (wet * G0),
		"dv": eng.isp_vac * G0 * log(wet / dry),
	}
