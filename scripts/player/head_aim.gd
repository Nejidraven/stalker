extends SkeletonModifier3D
## Наклон и поворот головы поверх анимации: при прицеливании от третьего лица голова
## склоняется к оружию и следит за вертикальным наклоном камеры.

var roll_deg: float = 0.0    # наклон к правому плечу
var pitch_deg: float = 0.0   # + вниз, - вверх

var _bone: int = -2


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bone == -2:
		_bone = sk.find_bone("Head")
	if _bone < 0 or (absf(roll_deg) < 0.01 and absf(pitch_deg) < 0.01):
		return
	var parent := sk.get_bone_parent(_bone)
	var g := sk.get_bone_global_pose(_bone)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var r := Basis(Vector3(0, 0, 1), deg_to_rad(roll_deg)) * Basis(Vector3(1, 0, 0), deg_to_rad(pitch_deg))
	var local := pg.affine_inverse() * Transform3D(r * g.basis, g.origin)
	sk.set_bone_pose_rotation(_bone, local.basis.get_rotation_quaternion())
