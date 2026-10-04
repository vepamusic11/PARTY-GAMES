extends RefCounted
## Censo de la memoria de texturas de la TV (para medir, no se usa en el
## juego): reparte `Performance.RENDER_TEXTURE_MEM_USED` entre lo que se
## puede contar desde GDScript. Lo usan tools/playtest.gd (--census) y
## tools/benchmark.gd. Ver docs/PERFORMANCE.md ("TV de poca memoria").
##
## Concepto: el motor solo da el total. Acá se suma lo que tiene cada dueño
## conocido (atlas de mascotas, tableros 2.5D, piezas 3D, viewports, fuentes,
## dioramas, texturas de nodos) con su tamaño en la placa (ancho × alto ×
## bytes por píxel, × 4/3 con mipmaps). Lo que no se puede atribuir queda en
## "otros" (buffers internos del render, texturas sin nodo).

const MIP := 4.0 / 3.0


## Diccionario nombre -> MB, con "total" y "otros".
static func take(tree: SceneTree) -> Dictionary:
	var out := {}
	var total := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	out["total"] = total / 1048576.0
	out["mascotas"] = MascotAtlas.memory_bytes() / 1048576.0
	var boards := 0.0
	for t: Texture2D in Board25DBaker._textures.values():
		boards += _tex_bytes(t)
	out["tableros"] = boards / 1048576.0
	out["tableros_n"] = Board25DBaker._textures.size()
	var props := Props3D.texture()
	out["piezas3d"] = (_tex_bytes(props) * MIP) / 1048576.0 if props != null else 0.0
	var vp_bytes := 0.0
	var vp_count := 0
	var tex_bytes := 0.0
	var seen := {}
	if tree != null and tree.root != null:
		# Ventana principal: color + profundidad.
		var rs := Vector2(tree.root.size)
		vp_bytes += rs.x * rs.y * 8.0
		vp_count += 1
		for n in tree.root.find_children("*", "", true, false):
			if n is SubViewport:
				var s := Vector2((n as SubViewport).size)
				# Color RGBA8 + profundidad (24+8) en los que tienen 3D.
				vp_bytes += s.x * s.y * (8.0 if not (n as SubViewport).disable_3d else 4.0)
				vp_count += 1
			var t: Texture2D = null
			if n is TextureRect:
				t = (n as TextureRect).texture
			elif n is Sprite2D:
				t = (n as Sprite2D).texture
			if t != null and not (t is ViewportTexture) and not seen.has(t):
				seen[t] = true
				tex_bytes += _tex_bytes(t)
	out["viewports"] = vp_bytes / 1048576.0
	out["viewports_n"] = vp_count
	out["nodos"] = tex_bytes / 1048576.0
	var dio := 0.0
	for t: Variant in GameCard._diorama_cache.values():
		if t is Texture2D and not seen.has(t):
			dio += _tex_bytes(t) * MIP
	out["dioramas"] = dio / 1048576.0
	out["fuentes"] = (_font_bytes(UiTheme.FONT_BOLD) + _font_bytes(UiTheme.FONT_SEMI)) / 1048576.0
	out["fuentes_n"] = _font_sizes(UiTheme.FONT_BOLD).size() + _font_sizes(UiTheme.FONT_SEMI).size()
	var known := 0.0
	for k in ["mascotas", "tableros", "piezas3d", "viewports", "nodos", "dioramas", "fuentes"]:
		known += float(out[k])
	out["otros"] = float(out.total) - known
	return out


## Línea corta para el log.
static func line(c: Dictionary) -> String:
	return "texturas %.1f MB = mascotas %.1f · tableros %.1f · piezas %.1f · viewports %.1f (%d) · nodos %.1f · dioramas %.1f · fuentes %.1f (%d tamaños) · otros %.1f" % [
		c.total, c.mascotas, c.tableros, c.piezas3d, c.viewports, c.viewports_n, c.nodos, c.dioramas, c.fuentes, c.fuentes_n, c.otros]


static func _tex_bytes(t: Texture2D) -> float:
	var bpp := 4.0
	if t is ImageTexture or t is CompressedTexture2D:
		var fmt := -1
		if t is ImageTexture:
			fmt = (t as ImageTexture).get_format()
		elif t is CompressedTexture2D:
			var img := (t as CompressedTexture2D).get_image()
			fmt = img.get_format() if img != null else -1
		match fmt:
			Image.FORMAT_RGB8:
				bpp = 3.0
			Image.FORMAT_L8:
				bpp = 1.0
			Image.FORMAT_LA8:
				bpp = 2.0
			Image.FORMAT_ETC2_RGBA8, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA:
				bpp = 1.0
			Image.FORMAT_ETC2_RGB8, Image.FORMAT_DXT1, Image.FORMAT_ETC:
				bpp = 0.5
	elif t is CanvasTexture:
		var d := (t as CanvasTexture).diffuse_texture
		return _tex_bytes(d) if d != null else 0.0
	return t.get_width() * t.get_height() * bpp


## Texturas de los cachés de glifos de una fuente dinámica (todas las
## combinaciones de tamaño y contorno que se dibujaron).
static func _font_bytes(f: Font) -> float:
	var ff := f as FontFile
	if ff == null:
		return 0.0
	var total := 0.0
	for c in ff.get_cache_count():
		for sz: Vector2i in ff.get_size_cache_list(c):
			for i in ff.get_texture_count(c, sz):
				var img := ff.get_texture_image(c, sz, i)
				if img != null:
					total += img.get_data().size()
	return total


## Tamaños de glifos cacheados de una fuente: [Vector2i(tamaño, contorno)].
static func _font_sizes(f: Font) -> Array:
	var ff := f as FontFile
	var out := []
	if ff == null:
		return out
	for c in ff.get_cache_count():
		out.append_array(ff.get_size_cache_list(c))
	return out


## Detalle de las fuentes (para buscar de dónde salen tantos tamaños).
static func font_detail() -> String:
	var parts := []
	for f: Font in [UiTheme.FONT_BOLD, UiTheme.FONT_SEMI]:
		var ff := f as FontFile
		for c in ff.get_cache_count():
			for sz: Vector2i in ff.get_size_cache_list(c):
				var b := 0
				for i in ff.get_texture_count(c, sz):
					var img := ff.get_texture_image(c, sz, i)
					b += img.get_data().size() if img != null else 0
				parts.append("%s c%d %d/%d: %d KB" % ["B" if f == UiTheme.FONT_BOLD else "S", c, sz.x, sz.y, b / 1024])
	return ", ".join(parts)
