extends SceneTree
## Exporta la música para escucharla fuera del juego (ADR 0015 y 0017):
##   - los jingles de marca sintetizados (core/audio/jingles.gd) a WAV;
##   - las pistas que compone MusicGen (estilos "generados") a WAV, con el
##     tiempo que tardó cada una;
##   - copia los .ogg de los estilos con archivos.
##
##   godot --headless --path . -s res://tools/render_music.gd -- --out=/tmp/musica
##   … -- --out=/tmp/musica --style=latino --track=lobby --bars=8 --seed=3
##
## Opciones: --style y --track filtran; --bars cambia el largo (16 por
## defecto); --seed suma una variación a la semilla de la receta.

func _initialize() -> void:
	var out := "/tmp/musica"
	var only_style := ""
	var only_track := ""
	var bars := -1
	var seed_offset := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--style="):
			only_style = arg.trim_prefix("--style=")
		elif arg.begins_with("--track="):
			only_track = arg.trim_prefix("--track=")
		elif arg.begins_with("--bars="):
			bars = int(arg.trim_prefix("--bars="))
		elif arg.begins_with("--seed="):
			seed_offset = int(arg.trim_prefix("--seed="))
	DirAccess.make_dir_recursive_absolute(out)
	if only_style.is_empty():
		for jingle_name: String in Jingles.SCORES:
			var t0 := Time.get_ticks_usec()
			var stream := Jingles.render(jingle_name)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var path := "%s/jingle_%s.wav" % [out, jingle_name]
			stream.save_to_wav(path)
			print("%-32s %.2f s  (sintetizado en %.1f ms)" % [path.get_file(), Jingles.duration(jingle_name), ms])
	for style: String in MusicStyles.ORDER:
		if not only_style.is_empty() and style != only_style:
			continue
		for track: String in MusicStyles.TRACK_NAMES:
			if not only_track.is_empty() and track != only_track:
				continue
			var src := MusicStyles.resolve(style, track)
			var dst := "%s/%s_%s" % [out, style, track]
			if src.has("generated") and str(src.generated) == style:
				var gen := MusicGen.new()
				var stream := gen.render_recipe(MusicGen.RECIPES[style][track], bars, seed_offset)
				stream.save_to_wav(dst + ".wav")
				var p := gen.profile
				if OS.get_cmdline_user_args().has("--melody"):
					print(melody_text(gen.lead_log, bars if bars > 0 else MusicGen.BARS))
				print("%-32s %5.1f s  compuesta en %5.0f ms (síntesis %d + mezcla %d, efectos %d, master %d)" % [
					(dst + ".wav").get_file(), stream.data.size() / 4.0 / MusicGen.MIX_RATE, p.total / 1000.0,
					p.synth / 1000, (p.compose_mix - p.synth) / 1000, p.effects / 1000, p.master / 1000])
			elif src.has("file") and str(src.file).begins_with(MusicStyles.MUSIC_DIR) and \
					(style == MusicStyles.RETRO or str(src.file).contains("/%s/" % style)):
				var bytes := FileAccess.get_file_as_bytes(str(src.file))
				var f := FileAccess.open(dst + ".ogg", FileAccess.WRITE)
				if f != null and not bytes.is_empty():
					f.store_buffer(bytes)
					f.close()
					print("%-32s %d KB" % [(dst + ".ogg").get_file(), bytes.size() / 1024])
	print("Listo: %s" % out)
	quit()


## Melodía como texto, un compás por línea: "Do5 . Mi5 ." (para revisarla).
static func melody_text(log: Array, bars: int) -> String:
	const NAMES := ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]
	var lines := PackedStringArray()
	for b in bars:
		var cells := PackedStringArray()
		for st in 16:
			var txt := "."
			for ev: Array in log:
				if int(ev[0]) == b * 16 + st:
					txt = "%s%d" % [NAMES[int(ev[1]) % 12], int(ev[1]) / 12 - 1]
			cells.append(txt)
		lines.append("  %2d | %s" % [b + 1, " ".join(cells)])
	return "\n".join(lines)
