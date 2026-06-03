class_name MaterialData
extends Resource

@export_group("Thresholds")
## Minimum energy to bore a hole.
@export var yield_strength: float = 40.0
## Energy at which damage reaches maximum size.
@export var ultimate_strength: float = 800.0

@export_group("Damage Shape")
## 0.0 = narrow deep needle (steel), 1.0 = wide shallow crater (wood).
@export_range(0.0, 1.0) var cavity_shape: float = 0.5

## Returns Vector2(radius, height). Zero vector means no mark.
func compute_hole(energy: float) -> Vector2:
	if energy <= 0.0:
		return Vector2.ZERO

	# Radius: scales with sqrt(energy/ultimate), width set by cavity_shape
	var t: float = sqrt(clamp(energy / ultimate_strength, 0.0, 1.0))
	var radius_max: float = lerpf(0.03, 0.16, cavity_shape)
	var radius: float = radius_max * t
	if radius < 0.005:
		return Vector2.ZERO

	var height: float
	if energy < yield_strength:
		# Sub-yield: shallow surface dent; soft materials dent more visibly
		var scratch_max: float = lerpf(0.005, 0.08, cavity_shape)
		height = lerpf(0.0, scratch_max, energy / yield_strength)
		if height < 0.003:
			return Vector2.ZERO
	else:
		# Above yield: always punch fully through
		height = 0.4

	return Vector2(radius, height)
