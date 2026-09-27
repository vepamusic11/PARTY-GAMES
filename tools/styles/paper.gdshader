// Estilo "paper": cartoon de libro ilustrado como post-proceso
// (exploración, ver docs/ESTILOS.md).
//
// 1. Contorno tembloroso: desplaza la lectura de la pantalla con ruido suave
//    (≈2 px), como una línea hecha a mano. El ruido cambia a 4 cuadros por
//    segundo ("boiling" de la animación dibujada a mano); `boil_fps = 0` lo
//    deja quieto.
// 2. Colores apenas desaturados y cálidos; el blanco pasa a papel crema.
// 3. Pigmento: donde hay color, su intensidad varía en manchas suaves de
//    ~25 px (como acuarela o gouache); el papel blanco queda limpio.
// 4. Textura de papel: grano fino multiplicado sobre todo.
// 5. Un leve oscurecimiento en los bordes de color (tinta que se acumula).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float wobble_px = 2.2;        // Amplitud del temblor (px en 1080p).
uniform float wobble_scale = 0.03;    // Frecuencia del temblor (1/px).
uniform float boil_fps = 4.0;
uniform float desaturate = 0.18;
uniform vec3 paper_color : source_color = vec3(0.984, 0.957, 0.902); // Crema #FBF4E6.
uniform float grain = 0.06;
uniform float pigment = 0.22;         // Variación del pigmento (0 = color plano).
uniform float ink_edges = 0.35;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	float scale = (1.0 / SCREEN_PIXEL_SIZE.y) / 1080.0;  // 1 en 1080p.
	vec2 frag = FRAGCOORD.xy / scale;                     // Coordenadas "1080p".
	float frame = boil_fps > 0.0 ? floor(TIME * boil_fps) : 0.0;
	vec2 seed = vec2(frame * 17.0, frame * 31.0);
	vec2 wob = vec2(value_noise(frag * wobble_scale + seed),
		value_noise(frag * wobble_scale + seed + vec2(40.0, 7.0))) - 0.5;
	vec2 uv = SCREEN_UV + wob * 2.0 * wobble_px * scale * SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, uv).rgb;

	// Tinta en los bordes: diferencia con 4 vecinos (a 2 px).
	vec2 d = 2.0 * scale * SCREEN_PIXEL_SIZE;
	float l0 = luma(c);
	float edge = abs(luma(texture(screen_tex, uv + vec2(d.x, 0.0)).rgb) - l0)
		+ abs(luma(texture(screen_tex, uv - vec2(d.x, 0.0)).rgb) - l0)
		+ abs(luma(texture(screen_tex, uv + vec2(0.0, d.y)).rgb) - l0)
		+ abs(luma(texture(screen_tex, uv - vec2(0.0, d.y)).rgb) - l0);
	edge = smoothstep(0.15, 0.9, edge);

	// Color: desaturado, un poco más suave de contraste y sobre papel crema.
	c = mix(c, vec3(luma(c)), desaturate);
	c = mix(vec3(0.5), c, 0.94) + 0.02;
	c *= paper_color;
	c = mix(c, c * vec3(0.55, 0.45, 0.42), edge * ink_edges);

	// Pigmento: aleja o acerca el color al papel en manchas suaves. En la
	// tinta casi negra (marcadores) casi no se nota: si no, parecen sucios.
	float blot = value_noise(frag * 0.04) * 0.65 + value_noise(frag * 0.11) * 0.35;
	float amount = pigment * smoothstep(0.12, 0.45, luma(c));
	c = paper_color - (paper_color - c) * (1.0 - amount * 0.5 + amount * blot);

	// Papel: grano fino (≈2 px) sobre todo.
	float fine = value_noise(frag * 0.55) * 0.7 + value_noise(frag * 1.7) * 0.3;
	c *= 1.0 - grain * fine;

	// Viñeta muy suave, como una página iluminada desde el centro.
	vec2 v = SCREEN_UV - 0.5;
	c *= 1.0 - dot(v, v) * 0.25;
	COLOR = vec4(c, 1.0);
}
