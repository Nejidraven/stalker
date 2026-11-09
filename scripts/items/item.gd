class_name Item
extends Resource
## Описание предмета (ресурс). Один файл .tres = один вид предмета.
## Сами предметы в рюкзаке хранятся как пары {item, count}, см. inventory.gd.

enum Category { MEDICINE, FOOD, AMMO, ARTIFACT, MISC, WEAPON }

@export var id: StringName
@export var display_name: String = "Предмет"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Вес одной штуки, кг
@export var weight: float = 0.1
@export var category: Category = Category.MISC
## Сколько штук помещается в одну ячейку
@export var max_stack: int = 1
## Сколько здоровья восстанавливает при использовании (0 = предмет не используется)
@export var heal_amount: float = 0.0
## Сколько лучевой болезни выводит при использовании (0 = не влияет на радиацию)
@export var radiation_reduce: float = 0.0
## Цвет временной 3D-заглушки на земле, пока нет настоящих моделей
@export var world_color: Color = Color(0.6, 0.6, 0.6)


func is_usable() -> bool:
	return heal_amount > 0.0 or radiation_reduce > 0.0


func category_name() -> String:
	match category:
		Category.MEDICINE:
			return "Медицина"
		Category.FOOD:
			return "Еда"
		Category.AMMO:
			return "Боеприпасы"
		Category.ARTIFACT:
			return "Артефакт"
		Category.WEAPON:
			return "Оружие"
		_:
			return "Разное"
