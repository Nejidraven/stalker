class_name Weapon
extends Item
## Огнестрельное оружие. Это обычный предмет рюкзака, поэтому его можно подбирать,
## выбрасывать и носить с собой. «Использовать» в рюкзаке берёт оружие в руки.
## Патроны берутся из рюкзака (ammo_id), текущий магазин хранит weapon_controller.gd.

@export_group("Оружие")
## Клавиша быстрого выбора: 1 или 2
@export_range(1, 9) var slot: int = 1
## id патронов (поле id у ресурса патронов в рюкзаке)
@export var ammo_id: StringName = &"ammo_545"
## Урон за одно попадание
@export var damage: float = 25.0
## Скорострельность, выстрелов в минуту
@export var fire_rate: float = 600.0
## Сколько дробинок вылетает за выстрел (дробовик); урон считается за каждую
@export var pellets: int = 1
@export var magazine_size: int = 30
@export var reload_time: float = 2.0
## Разброс в градусах (растёт при длинной очереди)
@export var spread_deg: float = 0.6
## Дальность, м
@export var max_range: float = 150.0
## Отдача камеры за выстрел, градусы
@export var recoil_pitch_deg: float = 1.0
@export var recoil_yaw_deg: float = 0.4
@export var can_single: bool = true
@export var can_auto: bool = false
## Холодное оружие: без патронов и прицела, ЛКМ — удар
@export var melee: bool = false
@export var melee_range: float = 1.9
## Наклон оружия вверх от первого лица (градусы)
@export var fp_pitch_deg: float = 0.0

@export_group("Вид и звук")
## Модель в руках (ствол направлен в -Z, как после экспорта из Blender)
@export var model_path: String = ""
## Где модель находится относительно руки
@export var hold_offset: Vector3 = Vector3(0.0, 0.0, -0.25)
## Где вылетает пуля, в координатах модели
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.03, -0.15)
## Временная модель рук (видна от первого лица), в тех же координатах, что и оружие
@export var hands_path: String = ""
## Какая поза рук от первого лица (анимации fp_<поза>_idle/walk/run): rifle или pistol
@export var fp_pose: StringName = &"rifle"
## Положение оружия относительно камеры при прицеливании: мушка на линии взгляда
@export var ads_offset: Vector3 = Vector3(0.0, -0.08, 0.05)
## Угол обзора при прицеливании (обычный задаётся камерой игрока)
@export var ads_fov: float = 60.0
@export var shot_sound_path: String = ""
@export var shot_volume_db: float = -14.0


func is_usable() -> bool:
	return true


func category_name() -> String:
	return "Оружие"
