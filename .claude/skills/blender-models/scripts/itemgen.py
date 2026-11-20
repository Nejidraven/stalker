"""itemgen - driver for building game-ready meshes + PBR textures in Blender
through the MCP for Blender tools, and exporting GLB for Godot.

Bootstrap from execute_blender_code:

    import sys, importlib
    sys.path.insert(0, r"<folder containing this file>")
    import itemgen as ig
    importlib.reload(ig)          # MCP exec caches modules between calls

VERIFIED HARD RULE (tested in Blender 5.2.3 -> glTF 2.0 -> Godot 4.7):
the glTF exporter DROPS procedural nodes. A Principled socket fed only by
Noise/Voronoi/Musgrave/ColorRamp/Bump exports as the glTF default - a test
material with Noise->ColorRamp->Roughness came out with no roughnessFactor
and no baseColorFactor at all. Only Image Texture nodes survive.
Every channel that must reach the engine is an Image Texture:
sRGB for colour, Non-Color for Roughness / Metallic / Normal.
"""
import bpy, numpy as np, math, os, importlib
from mathutils import Vector

# --------------------------------------------------------------- textures ---

def _resize_bilinear(a, oh, ow):
    ih, iw = a.shape[:2]
    y = np.clip((np.arange(oh) + 0.5) * ih / oh - 0.5, 0, ih - 1)
    x = np.clip((np.arange(ow) + 0.5) * iw / ow - 0.5, 0, iw - 1)
    y0 = np.floor(y).astype(int); x0 = np.floor(x).astype(int)
    y1 = np.minimum(y0 + 1, ih - 1); x1 = np.minimum(x0 + 1, iw - 1)
    wy = (y - y0)[:, None]; wx = (x - x0)[None, :]
    a00 = a[y0][:, x0]; a01 = a[y0][:, x1]
    a10 = a[y1][:, x0]; a11 = a[y1][:, x1]
    return a00 * (1 - wy) * (1 - wx) + a01 * (1 - wy) * wx + \
           a10 * wy * (1 - wx) + a11 * wy * wx


def fbm(w, h, octaves=5, base=4, rng=None, persistence=0.5):
    """Fractal noise in [0,1], shape (h, w). The workhorse for every map."""
    rng = rng if rng is not None else np.random.default_rng(7)
    total = np.zeros((h, w), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        gh = gw = max(2, base * (2 ** o))
        g = rng.random((gh, gw)).astype(np.float32)
        total += amp * _resize_bilinear(g, h, w)
        tot += amp; amp *= persistence
    return total / tot


def weave(w, h, period=6, rng=None):
    """Crosshatched fabric / gauze in [0,1]."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    p = float(period)
    a = np.abs(((xx % p) / p) * 2 - 1)
    b = np.abs(((yy % p) / p) * 2 - 1)
    v = np.maximum(a, b) ** 0.6
    return np.clip(v * 0.55 + fbm(w, h, octaves=3, base=32, rng=rng) * 0.45, 0, 1)


def make_image(name, rgba, data=False):
    """rgba: float32 (h, w, 4), top-down row order -> bpy image (packed).

    data=True marks it Non-Color (Roughness / Metallic / Normal maps).
    """
    rgba = np.ascontiguousarray(rgba, dtype=np.float32)
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, width=w, height=h, alpha=True, float_buffer=True)
    img.pixels.foreach_set(rgba[::-1].reshape(-1))   # Blender stores bottom-up
    if data:
        img.colorspace_settings.name = 'Non-Color'
    img.pack()
    return img


def data_image(name, arr2d, data=True):
    """Single-channel float array -> RGB image, Non-Color by default."""
    a = np.asarray(arr2d, np.float32)
    rgba = np.zeros(a.shape + (4,), np.float32)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = a
    rgba[..., 3] = 1.0
    return make_image(name, rgba, data=data)


def height_to_normal(h, strength=4.0):
    """Height field in [0,1] -> tangent-space OpenGL (+Y) normal map RGBA."""
    h = np.asarray(h, np.float32)
    gy, gx = np.gradient(h)
    nx = -gx * strength; ny = -gy * strength; nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5,
                     np.ones_like(h)], -1).astype(np.float32)


def solid(w, h, rgb, alpha=1.0):
    a = np.zeros((h, w, 4), np.float32)
    a[..., :3] = np.asarray(rgb, np.float32)
    a[..., 3] = alpha
    return a


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def grime(rgba, amount=0.25, rng=None, octaves=5):
    """Large-scale colour variation - breaks up the 'one flat colour' look."""
    h, w = rgba.shape[:2]
    n = fbm(w, h, octaves=octaves, base=8, rng=rng)
    out = rgba.copy()
    out[..., :3] *= (1.0 - amount + amount * n * 1.6)[..., None]
    return out


def scratches(rgba, count=40, length=(6, 40), rng=None, gain=0.35):
    """Fine bright scratches - the micro-detail that kills the CG look."""
    rng = rng if rng is not None else np.random.default_rng(3)
    h, w = rgba.shape[:2]
    out = rgba.copy()
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for _ in range(count):
        y0 = rng.uniform(0, h); x0 = rng.uniform(0, w)
        ang = rng.uniform(0, math.pi); ln = rng.uniform(*length)
        th = rng.uniform(0.6, 1.8)
        t = (xx - x0) * math.cos(ang) + (yy - y0) * math.sin(ang)
        d = np.abs(-(xx - x0) * math.sin(ang) + (yy - y0) * math.cos(ang))
        m = (t >= 0) & (t <= ln) & (d <= th)
        out[..., :3][m] = np.clip(out[..., :3][m] * (1 + gain), 0, 1)
    return out


FONT = {
    '0': ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    '1': ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    '2': ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    '3': ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    '4': ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    '5': ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    '6': ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    '7': ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    '8': ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    '9': ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    'x': ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
    'X': ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    '.': ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    '-': ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ' ': ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    'B': ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    'C': ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    'D': ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
    'E': ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    'F': ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    'G': ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    'H': ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    'I': ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    'K': ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    'M': ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    'N': ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    'P': ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    'R': ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    'T': ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    'U': ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    'V': ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    'W': ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    'Y': ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    'Z': ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}


def text_mask(shape, text, scale, cx, cy):
    """Boolean mask of bitmap text (Latin only). (cx, cy) = top-left."""
    h, w = shape
    m = np.zeros((h, w), bool)
    px = cx
    for ch in text:
        g = FONT.get(ch, FONT[' '])
        for r, row in enumerate(g):
            for c, bit in enumerate(row):
                if bit == '1':
                    y0 = cy + r * scale; x0 = px + c * scale
                    m[y0:y0 + scale, x0:x0 + scale] = True
        px += 6 * scale
    return m


def trefoil_mask(h, w, cx, cy, R):
    """Radiation trefoil: hub + 3 blades at 90 / 210 / 330 degrees."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = xx - cx; dy = yy - cy
    r = np.hypot(dx, dy)
    ang = np.degrees(np.arctan2(dy, dx))
    hub = r <= 0.24 * R
    blade = (r >= 0.24 * R) & (r <= 0.88 * R)
    for c in (90.0, 210.0, 330.0):
        d = np.abs(((ang - c + 180.0) % 360.0) - 180.0)
        blade &= d <= 26.0
    return hub | blade


def cross_mask(h, w, cx, cy, arm, thick):
    yy, xx = np.mgrid[0:h, 0:w]
    return (((np.abs(xx - cx) <= thick) | (np.abs(yy - cy) <= thick)) &
            ((np.abs(xx - cx) <= arm) & (np.abs(yy - cy) <= arm)))


def circle_mask(h, w, cx, cy, r):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    return np.hypot(xx - cx, yy - cy) <= r


# --------------------------------------------------------------- materials ---

def _sock(node, *names):
    for n in names:
        if n in node.inputs:
            return node.inputs[n]
    raise KeyError("%s has none of %s (has %s)" %
                   (node.type, names, list(node.inputs.keys())))


def bsdf(mat):
    """Principled BSDF node. ALWAYS look up by type: node names are localized."""
    return next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def channels(mat):
    """How each PBR socket is fed: 'image' | 'procedural' | 'value'.

    'procedural' means THAT CHANNEL IS LOST on glTF export. Read this
    before exporting - it is the single most common silent failure.
    """
    nt = mat.node_tree
    b = bsdf(mat)
    res = {}
    for label in ('Base Color', 'Metallic', 'Roughness', 'Normal', 'Alpha'):
        try:
            sock = _sock(b, label)
        except KeyError:
            continue
        if not sock.is_linked:
            res[label] = 'value'
            continue
        seen = set(); stack = [sock.links[0].from_node]; kinds = set()
        while stack and len(seen) < 40:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n); kinds.add(n.type)
            for inp in n.inputs:
                if inp.is_linked:
                    stack.append(inp.links[0].from_node)
        res[label] = 'image' if 'TEX_IMAGE' in kinds else (
            'procedural' if kinds else 'value')
    return res


def make_mat(name, image=None, rough=0.7, metal=0.0, emission=None,
             emission_strength=0.0, alpha=False, use_alpha_tex=False,
             base_color=None):
    """Simple material: optional colour image, constant roughness/metal.

    Only use this when a constant roughness is genuinely correct (painted
    sheet metal, plastic). Otherwise use make_mat_pbr.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.blend_method = 'BLEND' if alpha else 'OPAQUE'
    if alpha:
        m.use_backface_culling = True
    nt = m.node_tree
    b = bsdf(m)
    _sock(b, 'Roughness').default_value = rough
    _sock(b, 'Metallic').default_value = metal
    if emission is not None:
        _sock(b, 'Emission Color').default_value = emission
        _sock(b, 'Emission Strength').default_value = emission_strength
    if base_color is not None:
        _sock(b, 'Base Color').default_value = base_color
    if image is not None:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = image
        t.extension = 'EXTEND'
        nt.links.new(t.outputs['Color'], _sock(b, 'Base Color'))
        if use_alpha_tex:
            nt.links.new(t.outputs['Alpha'], _sock(b, 'Alpha'))
    return m


def make_mat_pbr(name, base=None, rough=None, normal=None, metallic=0.0,
                 roughness=0.7, alpha=False, emission=None,
                 emission_strength=0.0, base_color=None):
    """Full PBR material, export-safe.

    base   - sRGB colour image        -> Base Color
    rough  - Non-Color grey image     -> Roughness
    normal - Non-Color tangent map    -> Normal Map -> Normal
    metallic / roughness - constants (fallbacks + exported as factors)

    Metallic stays a per-material constant on purpose: split materials by
    physical type instead of trying to vary metalness inside one material.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.blend_method = 'BLEND' if alpha else 'OPAQUE'
    if alpha:
        m.use_backface_culling = True
    nt = m.node_tree
    b = bsdf(m)
    _sock(b, 'Roughness').default_value = roughness
    _sock(b, 'Metallic').default_value = metallic
    if base_color is not None:
        _sock(b, 'Base Color').default_value = base_color
    if emission is not None:
        _sock(b, 'Emission Color').default_value = emission
        _sock(b, 'Emission Strength').default_value = emission_strength
    if base is not None:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = base
        t.extension = 'RE PEAT'.replace(' ', '')
        nt.links.new(t.outputs['Color'], _sock(b, 'Base Color'))
        if alpha:
            nt.links.new(t.outputs['Alpha'], _sock(b, 'Alpha'))
    if rough is not None:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = rough
        t.extension = 'REPEAT'
        nt.links.new(t.outputs['Color'], _sock(b, 'Roughness'))
    if normal is not None:
        nm = nt.nodes.new('ShaderNodeNormalMap')
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = normal
        t.extension = 'REPEAT'
        nt.links.new(t.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], _sock(b, 'Normal'))
    return m


# ------------------------------------------------------------------- meshes ---

def deselect_all():
    bpy.ops.object.select_all(action='DESELECT')


def activate(obj):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    return obj


def shade_smooth(obj):
    bpy.ops.object.mode_set(mode='OBJECT')
    activate(obj)
    bpy.ops.object.shade_smooth()
    return obj


def box(name, size, location=(0, 0, 0), rotation=(0, 0, 0)):
    deselect_all()
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(scale=True)
    return o


def rounded_box(name, size, bevel=0.008, seg=3, location=(0, 0, 0)):
    o = box(name, size, location=location)
    if bevel > 0:
        mod = o.modifiers.new('Rnd', 'BEVEL')
        mod.width = bevel
        mod.segments = seg
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


def cyl(name, radius, depth, location=(0, 0, 0), rotation=(0, 0, 0), verts=32):
    deselect_all()
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth,
                                        location=location, rotation=rotation,
                                        vertices=verts)
    return activate(bpy.context.active_object)


def cone(name, r1, r2, depth, location=(0, 0, 0), rotation=(0, 0, 0), verts=24):
    deselect_all()
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth,
                                    location=location, rotation=rotation,
                                    vertices=verts)
    return activate(bpy.context.active_object)


def plane(name, size, location=(0, 0, 0), rotation=(0, 0, 0)):
    deselect_all()
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=location, rotation=rotation)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[1], 1.0)
    bpy.ops.object.transform_apply(scale=True)
    return activate(o)


def sphere(name, radius, location=(0, 0, 0), scale=(1, 1, 1), rings=16, segs=24):
    deselect_all()
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location,
                                         segments=segs, ring_count=rings)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return activate(o)


def bevel_hard(obj, width, segments=2, angle_deg=None):
    """Bevel that actually catches a highlight: Bevel (+ optional angle
    limit) + Weighted Normal, then smooth shading.

    Angle limiting is what keeps a box a box while its edges still catch
    light - without it a big bevel turns everything into a pillow.
    """
    mod = obj.modifiers.new('Bvl', 'BEVEL')
    mod.width = width
    mod.segments = segments
    if angle_deg is not None:
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(angle_deg)
    wn = obj.modifiers.new('WNrm', 'WEIGHTED_NORMAL')
    wn.keep_sharp = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=wn.name)
    shade_smooth(obj)
    return obj


def solidify(obj, thickness, offset=0.0):
    """Give a flat surface real thickness - never ship a single-sided plane."""
    mod = obj.modifiers.new('Solid', 'SOLIDIFY')
    mod.thickness = thickness
    mod.offset = offset
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def boolean(obj, cutter, operation='DIFFERENCE', apply=True):
    """Cut/union a real hole. Exact solver; works on closed meshes."""
    mod = obj.modifiers.new('Bool', 'BOOLEAN')
    mod.operation = operation
    mod.object = cutter
    try:
        mod.solver = 'EXACT'
    except Exception:
        pass
    if apply:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def join(objects, name):
    deselect_all()
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def add_mat(obj, mat, slot=0):
    """Assign material to slot (default 0), replacing any existing.

    Using slot=0 ensures faces with default material_index=0 use it.
    """
    while len(obj.data.materials) <= slot:
        obj.data.materials.append(None)
    obj.data.materials[slot] = mat
    # Ensure all faces point to this slot
    for p in obj.data.polygons:
        p.material_index = slot
    obj.data.update()
    return slot


def mat_by_normal(obj, axis, mapping, default=0):
    """Assign material slots by polygon normal. axis 0=x 1=y 2=z.
    mapping: {'+': slot, '-': slot}. Side faces keep `default`."""
    me = obj.data
    me.calc_loop_triangles()
    for p in me.polygons:
        v = (p.normal.x, p.normal.y, p.normal.z)[axis]
        key = '+' if v > 0.5 else ('-' if v < -0.5 else None)
        p.material_index = mapping.get(key, default)
    me.update()


def set_origin_bottom(obj):
    """Origin at the centre of the BOTTOM face - so instancing at (0,0,0)
    in Godot puts the model exactly on the ground. This is the placement
    contract for every pickup in this project.

    Works by shifting mesh vertices so bottom is at local Z=0, then
    placing the origin at (center_x, center_y, 0). No cursor/origin_set
    dance - avoids matrix_world stale-data issues.
    """
    activate(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    me = obj.data
    # Local bbox (rotation/scale applied, so local == world)
    min_z = min(v.co.z for v in me.vertices)
    max_z = max(v.co.z for v in me.vertices)
    center_x = sum(v.co.x for v in me.vertices) / len(me.vertices)
    center_y = sum(v.co.y for v in me.vertices) / len(me.vertices)
    # Shift mesh up so bottom sits at z=0
    if min_z != 0.0:
        for v in me.vertices:
            v.co.z -= min_z
        me.update()
    # Place origin at bottom-center
    bpy.context.scene.cursor.location = (center_x, center_y, 0.0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    obj.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    return obj


def cylinder_side_uv(obj):
    """Cylindrical UV on the side faces only (object axis must be Z).

    Use this whenever a texture marking must appear EXACTLY ONCE around a
    bottle/can - a default cube UV would tile it 4x.
    """
    activate(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in obj.data.polygons:
        p.select = abs(p.normal.z) < 0.9
    bpy.ops.object.mode_set(mode='EDIT')
    try:
        bpy.ops.uv.cylinder_project(direction='ALIGN_TO_OBJECT')
    except TypeError:
        bpy.ops.uv.cylinder_project()
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def marking_azimuth(obj, u=0.5, v=0.5):
    """World azimuth (radians, +X toward +Y) of UV point (u, v)."""
    me = obj.data
    uv = me.uv_layers.active.data
    best = None
    for p in me.polygons:
        if abs(p.normal.z) >= 0.9:
            continue
        for li in p.loop_indices:
            d = (uv[li].uv - Vector((u, v))).length
            if best is None or d < best[0]:
                best = (d, me.vertices[me.loops[li].vertex_index].co.copy())
    if best is None:
        return None
    co = obj.matrix_world @ best[1]
    return math.atan2(co.y, co.x)


def lay_down_marking_up(obj, u=0.5, v=0.5, spin_extra=0.0):
    """Spin a Z-axis cylinder so UV (u,v) faces up, then lay it along +X."""
    az = marking_azimuth(obj, u, v)
    if az is not None:
        obj.rotation_euler.z += (math.radians(90.0) - az)
    activate(obj)
    bpy.ops.object.transform_apply(rotation=True)
    obj.rotation_euler.y = math.radians(90.0) + spin_extra
    bpy.ops.object.transform_apply(rotation=True)
    return obj


# ------------------------------------------------------- report + export ---

def report(obj, label=''):
    """Print the quality facts for the validation loop. READ THE OUTPUT."""
    import bmesh
    me = obj.data
    me.calc_loop_triangles()
    dg = bmesh.new(); dg.from_mesh(me)
    loose = sum(1 for v in dg.verts if not v.link_faces)
    nonman = sum(1 for e in dg.edges if len(e.link_faces) != 2)
    dg.free()
    vs = [obj.matrix_world @ v.co for v in me.vertices]
    mn = [min(v[i] for v in vs) for i in range(3)]
    mx = [max(v[i] for v in vs) for i in range(3)]
    ngons = sum(1 for p in me.polygons if len(p.vertices) > 4)
    tris = sum(1 for p in me.polygons if len(p.vertices) == 3)
    print('--- %s%s' % (label or obj.name, ''))
    print('  size      %.4f x %.4f x %.4f m' % tuple(mx[i] - mn[i] for i in range(3)))
    print('  bbox min  (%.4f, %.4f, %.4f)   scale %s' %
          (mn[0], mn[1], mn[2], tuple(round(s, 4) for s in obj.scale)))
    print('  mesh      %d polys  %d tris  %d ngons  %d loose  %d non-manifold'
          % (len(me.polygons), tris, ngons, loose, nonman))
    bad = []
    for slot in obj.material_slots:
        if slot.material is None:
            continue
        ch = channels(slot.material)
        lost = [k for k, v in ch.items() if v == 'procedural']
        print('  mat %-22s %s%s' % (slot.material.name, ch,
                                    '   <-- LOST ON EXPORT: ' + ','.join(lost)
                                    if lost else ''))
        if lost:
            bad.append((slot.material.name, lost))
    if ngons or loose or nonman:
        print('  WARN topology: ngons=%d loose=%d non-manifold=%d'
              % (ngons, loose, nonman))
    if tuple(round(s, 4) for s in obj.scale) != (1.0, 1.0, 1.0):
        print('  WARN scale not applied')
    if abs(mn[2]) > 1e-4:
        print('  WARN origin not on the ground (min z = %.4f)' % mn[2])
    return {'size': [mx[i] - mn[i] for i in range(3)], 'min_z': mn[2],
            'ngons': ngons, 'loose': loose, 'nonmanifold': nonman,
            'lost_channels': bad}


def clean_scene(keep=()):
    for o in list(bpy.data.objects):
        if o.name in keep:
            continue
        bpy.data.objects.remove(o, do_unlink=True)


def export_glb(filepath, objects):
    """Export GLB for Godot: Y-up, no cameras/lights/animations, embedded PNG."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    deselect_all()
    for o in objects:
        o.select_set(True)
    kw = dict(
        filepath=filepath, export_format='GLB', use_selection=True,
        export_apply=True, export_yup=True, export_animations=False,
        export_skins=False, export_morph=False, export_cameras=False,
        export_lights=False, export_extras=False,
        export_image_format='AUTO', export_try_ogga=True,
    )
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop('export_try_ogga', None)
        kw.pop('export_image_format', None)
        bpy.ops.export_scene.gltf(**kw)
    return filepath
