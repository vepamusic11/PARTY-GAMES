// Estilo "neon": noche de arcade como post-proceso (exploración, ver docs/ESTILOS.md).
//
// Trabaja en OKLab (brillo L + tono/saturación a, b), que permite cambiar el
// brillo sin que el tono se corra.
// 1. Superficies neutras (papel, cielo, pantallas oscuras de los marcadores)
//    pasan a ser "noche": oscuras y con un tinte violeta.
// 2. Trazos neutros finos (letras, números, íconos) pasan a ser luz, estén
//    sobre papel blanco o sobre una pantalla oscura: el texto sigue legible.
//    Qué es "superficie" y qué es "trazo" se decide con promedios de la zona
//    (mipmaps de la pantalla, ~11 y ~24 px), no con muestras sueltas, que
//    dejaban "ecos" de los bordes. Tinta sobre papel claro -> trazo; blanco
//    pegado a algo oscuro y lejos del papel -> trazo; el resto, superficie.
//    El cielo cuenta como oscuro (va a ser noche): el título blanco con
//    contorno sobre el cielo sigue blanco. Texto oscuro sobre un color vivo
//    (botón amarillo) queda oscuro.
// 3. Los colores vivos (jugadores, bloques, foco amarillo) conservan el tono
//    y suben de brillo y saturación.
// 4. Brillo "barato" (glow): dos mipmaps más borrosos (~16 y ~64 px) aportan
//    la luz de los colores vivos cercanos. Sin muestras sueltas no hay
//    "ecos" de los bordes. Se mezcla en modo "trama" (screen), que nunca
//    pasa de blanco: el texto no se quema.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float glow_strength = 0.55;
// Tinte de la noche (a, b de OKLab): violeta azulado.
uniform vec2 night_tint = vec2(0.025, -0.07);

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec3 oklab(vec3 srgb) {
	vec3 c = to_linear(srgb);
	vec3 lms = vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

vec3 from_oklab(vec3 lab) {
	vec3 lms = vec3(
		lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	lms = lms * lms * lms;
	return to_srgb(vec3(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z));
}

// 1 si el color es el cielo del fondo (celeste de tono ~-120° en OKLab y
// saturación media), 0 si no.
float sky_mask(vec3 lab) {
	float chroma = length(lab.yz);
	float hue = degrees(atan(lab.z, lab.y));
	return (1.0 - smoothstep(6.0, 10.0, abs(hue + 120.0)))
		* smoothstep(0.02, 0.03, chroma) * (1.0 - smoothstep(0.136, 0.145, chroma))
		* smoothstep(0.55, 0.68, lab.x);
}

// Qué tan "vivo" es un color (0 = neutro o cielo, 1 = color de juego).
// `from` baja el umbral para los promedios de zona, que al mezclar el color
// con la tinta del texto pierden saturación.
float vividness(vec3 lab, float from) {
	return smoothstep(from, from + 0.045, length(lab.yz)) * (1.0 - sky_mask(lab));
}

// Color vivo "encendido": mismo tono, más brillo y saturación.
vec3 lit(vec3 lab) {
	return vec3(max(lab.x, 0.74), lab.yz * 1.35);
}

// Clase de una zona: 1 = papel claro; 0 = oscura, color vivo o cielo (el
// cielo va a ser noche, así que el texto blanco sobre él queda blanco).
// Exigente con el brillo: una zona mitad blanca y mitad oscura (un número
// blanco sobre un marcador) ya tiene L ~0,6 y no cuenta como papel.
float light_class(vec3 lab, float w) {
	return (1.0 - w) * (1.0 - sky_mask(lab)) * smoothstep(0.65, 0.85, lab.x);
}

void fragment() {
	// Los mipmaps se eligen para que el efecto mida lo mismo en 720p, 1080p o 4K.
	float lod0 = log2((1.0 / SCREEN_PIXEL_SIZE.y) / 1080.0);
	vec3 lab = oklab(textureLod(screen_tex, SCREEN_UV, 0.0).rgb);
	// Umbral bajo para que los bloques pastel del fondo sigan siendo de color;
	// la condición de brillo deja afuera a la tinta (azul muy oscuro).
	float w = vividness(lab, 0.05) * smoothstep(0.4, 0.55, lab.x);
	float light = smoothstep(0.45, 0.65, lab.x);

	// Zona grande (~24 px): ¿el píxel está sobre papel claro?
	vec3 zone = oklab(textureLod(screen_tex, SCREEN_UV, lod0 + 4.5).rgb);
	float zone_vivid = vividness(zone, 0.035);
	float zone_light = light_class(zone, zone_vivid);
	// Zona chica (~11 px): ¿hay algo oscuro pegado (contorno, marcador)?
	// (Se probó con 8 muestras sueltas en estrella: dejaba "ecos" punteados
	// en los títulos. El mipmap da un promedio suave y sin ruido.)
	float near_dark = 1.0 - smoothstep(0.72, 0.88, oklab(textureLod(screen_tex, SCREEN_UV, lod0 + 3.5).rgb).x);
	// Para la tinta alcanza con que la zona sea "bastante" clara y neutra: en
	// un párrafo denso la tinta oscurece mucho el promedio.
	float ink_on_paper = (1.0 - zone_vivid) * (1.0 - sky_mask(zone)) * smoothstep(0.52, 0.68, zone.x);
	// Trazo oscuro = tinta sobre papel claro (texto de las tarjetas).
	// Trazo claro = blanco pegado a algo oscuro y lejos de papel claro
	// (números de los marcadores, títulos blancos con contorno sobre el cielo).
	// El resto es superficie. El cielo siempre es superficie.
	float stroke = mix(ink_on_paper, near_dark * (1.0 - smoothstep(0.6, 0.9, zone_light)), light);
	stroke *= 1.0 - sky_mask(lab);

	// Neutros: superficie -> noche; trazo -> luz.
	float l_surface = mix(0.13 + 0.3 * lab.x, 0.16 + 0.22 * (1.0 - lab.x), light);
	float l_stroke = mix(0.95 - 0.35 * lab.x, max(lab.x, 0.92), light);
	float l_neutral = mix(l_surface, l_stroke, stroke);
	vec2 ab_neutral = lab.yz + night_tint * (1.0 - smoothstep(0.3, 0.7, l_neutral));
	vec3 base = from_oklab(mix(vec3(l_neutral, ab_neutral), lit(lab), w));

	// Brillo de los colores vivos cercanos, desde dos mipmaps borrosos. Solo
	// alrededor de los objetos (halo), no adentro: el texto oscuro de un
	// botón amarillo no se tiñe.
	vec3 near = oklab(textureLod(screen_tex, SCREEN_UV, lod0 + 4.0).rgb);
	vec3 far = oklab(textureLod(screen_tex, SCREEN_UV, lod0 + 6.0).rgb);
	vec3 glow = from_oklab(lit(near)) * vividness(near, 0.06) * 0.7
		+ from_oklab(lit(far)) * vividness(far, 0.06) * 0.45;
	glow *= glow_strength * (1.0 - 0.85 * zone_vivid);
	// Mezcla "trama": suma luz sin pasar de blanco.
	COLOR = vec4(1.0 - (1.0 - base) * (1.0 - glow), 1.0);
}
