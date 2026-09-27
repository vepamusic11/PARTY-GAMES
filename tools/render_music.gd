extends SceneTree
## Exporta los jingles de marca sintetizados (core/audio/jingles.gd) a WAV
## para escucharlos fuera del juego, y lista las pistas de música en OGG.
##
##   godot --headless --path . -s res://tools/render_music.gd -- --out=/tmp/musica
##
## Las pistas de assets/audio/music/ ya son archivos (CC0, ver CREDITS.md):
## se copian al mismo directorio para tener todo junto.

func _initialize() -> void:
	var out := "/tmp/musica"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	for jingle_name: String in Jingles.SCORES:
		var t0 := Time.get_ticks_usec()
		var stream := Jingles.render(jingle_name)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var path := "%s/jingle_%s.wav" % [out, jingle_name]
		stream.save_to_wav(path)
		print("%-28s %.2f s  (sintetizado en %.1f ms)" % [path.get_file(), Jingles.duration(jingle_name), ms])
	for track: String in Music.TRACKS:
		var src: String = Music.TRACKS[track]
		var dst := "%s/%s.ogg" % [out, track]
		var bytes := FileAccess.get_file_as_bytes(src)
		var f := FileAccess.open(dst, FileAccess.WRITE)
		if f != null and not bytes.is_empty():
			f.store_buffer(bytes)
			f.close()
			print("%-28s %d KB" % [dst.get_file(), bytes.size() / 1024])
	print("Listo: %s" % out)
	quit()
