extends CharacterBody3D
## Игрок от третьего лица: ходьба, бег, прыжок, камера на SpringArm3D.

@export var walk_speed: float = 4.0
@export var run_speed: float = 7.5
@export var jump_velocity: float = 5.0
@export var ground_acceleration: float = 12.0
@export var air_acceleration: float = 3.0
@export var model_turn_speed: float = 10.0
@export_group("Camera")
@export var mouse_sensitivity: float = 0.003
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 25.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var visual: Node3D = $Visual

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Камера не должна упираться в коллизию самого игрока
	spring_arm.add_excluded_object(get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotation.x = clampf(
			spring_arm.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
	elif event.is_action_pressed("ui_cancel"):
		# Esc освобождает/возвращает курсор
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Движение относительно направления камеры (поворачивается только CameraPivot)
	var direction := camera_pivot.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()

	var target_speed := run_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_acceleration if is_on_floor() else air_acceleration
	var weight := clampf(accel * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, direction.x * target_speed, weight)
	velocity.z = lerpf(velocity.z, direction.z * target_speed, weight)

	# Поворачиваем модель в сторону движения
	if direction.length_squared() > 0.001:
		var target_yaw := atan2(-direction.x, -direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, model_turn_speed * delta)

	move_and_slide()
