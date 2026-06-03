class_name MaterialData
extends Resource

@export_group("Thresholds")
## Minimum energy to bore a hole (plastic deformation begins).
@export var yield_strength: float = 40.0
## Reserved for M4 catastrophic failure (splitting). Not used yet.
@export var ultimate_strength: float = 200.0
