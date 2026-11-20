---
name: blender-models
description: Create production-ready 3D models and PBR textures in Blender via MCP-for-Blender tools and export GLB for Godot. Use when asked to model, texture, re-make, or fix a 3D asset (pickups, props, weapons, characters), when a model "looks bad/plastic/flat/wrong", or before exporting any mesh to assets/*.glb.
---

# Blender Models Skill

Полный пайплайн: референс → блокинг → вторичные формы → детали → UV + PBR карты-изображения → валидация → GLB экспорт. Работает в окружении: **Blender 5.2.3 LTS + MCP-for-Blender addon + Godot 4.7.2**.

---

## 🔴 ОДНО ЖЁСТКОЕ ПРАВИЛО (проверено в продакшене)

**Процедурные ноды НЕ экспортятся в glTF.** Материал с `Noise → ColorRamp → Roughness` вылетит в GLB БЕЗ roughnessFactor и БЕЗ baseColorFactor — glTF будет использовать дефолты (roughness=0.5, серый цвет). Проверено: тестовый материал потерял все каналы.

**Решение:** каждый PBR-канал, который должен доехать до движка — это **Image Texture нода**:
- Base Color → sRGB
- Roughness / Metallic / Normal → **Non-Color** (важно: `img.colorspace_settings.name = 'Non-Color'`)
- Никаких Bump/ColorRamp/Math между текстурой и сокетом — только прямая ссылка.

---

## 1. ПАЙПЛАЙН (6 этапов)

### Этап 0 — Референс и пропорции
- Реальные физические размеры в метрах (1 BU = 1 м). Игрок ~1.8 м.
- Декомпозиция на примитивы с таблицей размеров (X, Y, Z) **до** открытия Blender.
- Разделение на функциональные части: корпус, крепежи, подвижные узлы, ткань, фурнитура — отдельные меши.

### Этап 1 — Блокинг (Primary forms)
- Только крупные объёмы, по одному мешу на часть.
- `look` с фронтом, боком, сверху, three_quarter — силуэт должен совпадать с референсом.
- Никаких деталей, фасок, вырезов.

### Этап 2 — Вторичные формы (Secondary forms)
- Вырезы (boolean DIFFERENCE), фаски, стыки панелей, изгибы.
- **Solidify** для тонких стенок/ткани/металла — ноль односторонних плоскостей.
- **Bevel + Weighted Normal** (angle limit ~35°) — грани ловят блики, не "подушки".
- Модификаторы не применяем до этапа 4.

### Этап 3 — Мелкие детали (Tertiary forms)
- Болты, швы, заклепки, микрорельеф, потертости.
- Лёгкая асимметрия: вариации расположения, складки, износ.

### Этап 4 — UV + PBR текстуры (только карты-изображения)
- UV без сильных растяжений, равномерная плотность текселей. Швы в скрытых местах.
- Материалы строго по физике: металл (Metallic=1, низкий Roughness) / диэлектрики (Metallic=0).
- **Генерация карт в numpy** (в Blender нет PIL):
  - `fbm` — фрактальный шум для roughness/grime/ao
  - `weave` — ткань/марля
  - `height_to_normal` → OpenGL tangent-space normal map
  - `scratches`, `grime` — микродетали
- Все текстуры пакуются в `.png` внутри `.blend` (`img.pack()`).
- Материал собирается через `make_mat_pbr(base, rough, normal, metallic=0|1)`.

### Этап 5 — Экспорт и размещение (контракт Godot)
- `Apply Scale & Rotation` (scale = 1,1,1).
- **Origin в центре нижней грани** (local min Z = 0) — `set_origin_bottom(obj)`. При инстанцировании в (0,0,0) предмет стоит ровно на полу.
- `export_glb(filepath, [obj])`: GLB, Y-up, embedded PNG, без камер/ламп/анимаций.
- Реимпорт в Blender для проверки: `bbox_z: 0.0 → max`.

---

## 2. БУТСТРАП (первая строчка в execute_blender_code)

```python
import sys, importlib
sys.path.insert(0, r"C:/Users/User/Documents/stalker-zone/.claude/skills/blender-models/scripts")
import itemgen as ig
importlib.reload(ig)          # MCP exec кэширует модули между вызовами!
```

> **Важно:** без `importlib.reload` изменения в `itemgen.py` не подхватятся — Blender использует закешированную версию.

---

## 3. КЛЮЧЕВЫЕ ХЕЛПЕРЫ (itemgen.py — проверенные в этой сессии)

| Категория | Функции |
|---|---|
| **Текстуры** | `fbm(w,h)`, `weave(w,h)`, `make_image(name,rgba,data)`, `data_image(name,arr2d)`, `height_to_normal(h)`, `solid`, `mix`, `grime`, `scratches`, `text_mask`, `trefoil_mask`, `cross_mask`, `circle_mask` |
| **Материалы** | `bsdf(mat)` — поиск по типу (имена локализованы), `channels(mat)` → `{'Base Color':'image'|'procedural'|'value',...}` — **читать перед экспортом**, `make_mat_pbr(name, base, rough, normal, metallic=0)` — export-safe PBR |
| **Меши** | `box/cyl/cone/plane/sphere`, `rounded_box`, `bevel_hard(obj,w,seg,angle)`, `solidify(obj,thickness)`, `boolean(obj,cutter,'DIFFERENCE')`, `join(objs,name)`, `add_mat(obj,mat,slot=0)`, `mat_by_normal`, `shade_smooth` |
| **UV / Ориентация** | `cylinder_side_uv(obj)` — цилиндрическая проекция для бутылок/банок, `marking_azimuth(obj,u,v)` → азимут UV-точки, `lay_down_marking_up(obj)` — повернуть так, чтобы метка смотрела вверх |
| **Валидация / Экспорт** | `report(obj)` — печатает размеры, bbox min_z, ngons, loose, non-manifold, **lost_channels**, `clean_scene(keep=())`, `export_glb(path, objects)` |

---

## 4. ВАЛИДАЦИОННЫЙ ЦИКЛ (обязательно после каждого изменения)

```python
rep = ig.report(obj)          # читаем вывод!
# Должно быть:
#   bbox min z = 0.0000
#   scale = (1.0, 1.0, 1.0)
#   lost_channels = []        (нет 'procedural')
#   ngons = 0 (или минимально)
#   no loose / non-manifold
```

Если `report` показывает `'procedural'` в любом канале — **материал сломается в Godot**. Исправь: замени ноду на Image Texture.

После экспорта — `look` импортированного GLB в Blender (File → Import → glTF) и проверь `bbox_z`.

---

## 5. ОКРУЖЕНИЕ — ПРОВЕРЕННЫЕ ГОТЧИ

| Проблема | Решение |
|---|---|
| Имена нод локализованы ("Куб", "Принципиальный BSDF") | Только `node.type == 'BSDF_PRINCIPLED'`, `node.type == 'TEX_IMAGE'` |
| Enum-идентификаторы меняются между версиями | `try: bpy.ops.uv.cylinder_project(direction='ALIGN_TO_OBJECT') except TypeError: bpy.ops.uv.cylinder_project()` |
| Модули кэшируются между `execute_blender_code` | Обязательный `importlib.reload(ig)` после импорта |
| `look` требует `target` как список | `look(target=["MyObject"])` |
| Blender Z-up → Godot Y-up | `export_yup=True` в экспортере |
| В Blender нет PIL / Pillow | Генерация текстур только через `numpy` + `img.pixels.foreach_set` |
| Бенедиктные предупреждения (игнорировать) | "More than one shader node tex image used for a texture" (alpha-декаль), "ObjectDB instances were leaked at exit" (headless quit) |

---

## 6. МИНИМАЛЬНЫЙ ПРИМЕР (smoke test — запускать для проверки среды)

```python
import sys, importlib, numpy as np
sys.path.insert(0, r"C:/Users/User/Documents/stalker-zone/.claude/skills/blender-models/scripts")
import itemgen as ig
importlib.reload(ig)

ig.clean_scene()
rng = np.random.default_rng(42)
h = ig.fbm(256,256, octaves=5, base=8, rng=rng)
base = ig.make_image("B", ig.grime(ig.solid(256,256,(0.3,0.3,0.2)), rng=rng), data=False)
rough = ig.data_image("R", np.clip(0.3+h*0.5, 0.15, 0.95), data=True)
norm = ig.make_image("N", ig.height_to_normal(h), data=True)
mat = ig.make_mat_pbr("M", base=base, rough=rough, normal=norm, metallic=0.0)

obj = ig.box("Test", (0.2,0.1,0.05))
ig.bevel_hard(obj, 0.003, 2, 35)
ig.add_mat(obj, mat)
ig.set_origin_bottom(obj)

rep = ig.report(obj)          # <-- ОБЯЗАТЕЛЬНО читать
ig.export_glb("C:/.../_smoke.glb", [obj])
ig.clean_scene()
```

Ожидаемый `report`: `min_z = 0.0000`, `scale = (1.0, 1.0, 1.0)`, `lost_channels = []`, все каналы `'image'`.

---

## 7. АНТИ-ПАТТЕРНЫ (что делали плохо — не повторять)

| Было ❌ | Стало ✅ |
|---|---|
| Один куб + bevel на всё | Декомпозиция на части, boolean, solidify |
| Однотонный Roughness = 0.7 | `fbm` + `grime` + `scratches` → карта roughness |
| Нет normal map | `height_to_normal` из height field |
| Procedural ноды в материале | Только Image Texture (Non-Color для данных) |
| Origin в центре объёма | `set_origin_bottom` → min_z = 0 |
| Scale не применён | `Apply Scale & Rotation` перед детализацией |
| Плоские детали без толщины | `solidify` + `bevel_hard` |
| Идеальная стерильность | `grime` (крупный шум) + `scratches` (микро) |

---

## 8. ФАЙЛЫ СКИЛЛА

```
.claude/skills/blender-models/
├── SKILL.md              ← этот файл
└── scripts/
    └── itemgen.py        ← драйвер-библиотека (загружается через bootstrap выше)
```

Полный код `itemgen.py` содержит все хелперы выше — он **уже лежит рядом** и проходит смок-тест.

---

> **Напоминание:** каждый запуск в `execute_blender_code` начинается с чистого состояния Blender (кроме закешированных модулей). Всегда делай `clean_scene()` в начале, `importlib.reload(ig)` после импорта, и `report(obj)` перед экспортом.