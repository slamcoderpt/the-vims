extends Node3D
## Placeholder location. To be replaced by its builder.

func build() -> void:
	var vb := VoxelBuilder.new()
	vb.box(Vector3i(-40, -1, -40), Vector3i(80, 1, 80), Color(0.55, 0.42, 0.3))
	vb.box(Vector3i(-4, 0, -4), Vector3i(8, 12, 8), Color(0.8, 0.3, 0.3))
	add_child(vb.build_instance(0.125))
