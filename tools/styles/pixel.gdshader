// Estilo "pixel": pixel art retro como post-proceso (exploración, ver docs/ESTILOS.md).
//
// 1. Baja la pantalla a una grilla de `pixel_height` filas (el ancho sale del
//    aspecto: 640×360 en la TV 16:9) promediando 4 muestras de cada celda,
//    así las líneas finas (contornos, letras) no desaparecen al azar.
// 2. Opcional: dithering ordenado Bayer 4×4 sobre la grilla baja.
// 3. Cuantiza cada celda al color más cercano de una paleta limitada,
//    comparando en OKLab (se parece más a cómo percibimos la diferencia).
//
// Paleta: 24 de los 64 colores de "Resurrect 64", de Kerrie Lake
// (lospec.com/palette-list/resurrect-64). Su autora la publicó para uso libre;
// una lista de colores no está sujeta a derechos de autor, así que se puede
// usar en el producto (igual la citamos). Se eligieron los tonos más cercanos
// a los tokens de UiTheme: cielo, tinta, foco amarillo y los 4 colores de jugador.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Filas de la grilla baja: 270 = píxel de 4×4 en 1080p, 360 = de 3×3.
uniform float pixel_height = 360.0;
uniform bool dither = true;
// Cuánto mueve el dithering cada canal antes de cuantizar (0 = sin tramado).
uniform float dither_strength = 0.05;

const int PALETTE_SIZE = 24;
const vec3 PALETTE[24] = {
	vec3(0.180, 0.133, 0.184), // #2e222f tinta / contornos
	vec3(0.196, 0.200, 0.325), // #323353 fondo de marcadores
	vec3(0.282, 0.290, 0.467), // #484a77 texto secundario
	vec3(0.498, 0.439, 0.541), // #7f708a
	vec3(0.608, 0.671, 0.698), // #9babb2 deshabilitado
	vec3(0.780, 0.863, 0.816), // #c7dcd0 papel en sombra
	vec3(1.000, 1.000, 1.000), // #ffffff papel
	vec3(0.682, 0.137, 0.204), // #ae2334
	vec3(0.910, 0.231, 0.231), // #e83b3b rojo 1P
	vec3(0.965, 0.506, 0.506), // #f68181
	vec3(0.984, 0.420, 0.114), // #fb6b1d
	vec3(0.969, 0.588, 0.090), // #f79617 naranja 3P
	vec3(0.976, 0.761, 0.169), // #f9c22b foco del D-pad
	vec3(0.137, 0.565, 0.388), // #239063 verde 4P
	vec3(0.118, 0.737, 0.451), // #1ebc73
	vec3(0.569, 0.859, 0.412), // #91db69
	vec3(0.055, 0.686, 0.608), // #0eaf9b
	vec3(0.302, 0.396, 0.706), // #4d65b4
	vec3(0.302, 0.608, 0.902), // #4d9be6 azul 2P / cielo
	vec3(0.561, 0.827, 1.000), // #8fd3ff cielo claro
	vec3(0.420, 0.243, 0.459), // #6b3e75
	vec3(0.659, 0.518, 0.953), // #a884f3
	vec3(0.941, 0.310, 0.471), // #f04f78
	vec3(0.918, 0.678, 0.929)  // #eaaded
};
// Los mismos colores ya pasados a OKLab (precalculado: ahorra 24 raíces
// cúbicas por píxel).
const vec3 PALETTE_LAB[24] = {
	vec3(0.2716, 0.0235, -0.0172),
	vec3(0.3356, 0.0112, -0.0548),
	vec3(0.4280, 0.0139, -0.0728),
	vec3(0.5682, 0.0282, -0.0326),
	vec3(0.7309, -0.0144, -0.0148),
	vec3(0.8754, -0.0262, 0.0091),
	vec3(1.0000, 0.0000, 0.0000),
	vec3(0.4925, 0.1625, 0.0608),
	vec3(0.6158, 0.1885, 0.0915),
	vec3(0.7342, 0.1337, 0.0518),
	vec3(0.6971, 0.1402, 0.1335),
	vec3(0.7574, 0.0716, 0.1496),
	vec3(0.8408, 0.0102, 0.1620),
	vec3(0.5821, -0.1119, 0.0393),
	vec3(0.7021, -0.1490, 0.0657),
	vec3(0.8178, -0.1185, 0.1154),
	vec3(0.6768, -0.1204, -0.0014),
	vec3(0.5269, -0.0022, -0.1274),
	vec3(0.6736, -0.0470, -0.1273),
	vec3(0.8374, -0.0493, -0.0781),
	vec3(0.4404, 0.0780, -0.0652),
	vec3(0.6940, 0.0729, -0.1433),
	vec3(0.6592, 0.1951, 0.0314),
	vec3(0.8247, 0.0897, -0.0629)
};

// Matriz de Bayer 4×4 (umbrales 0..15).
const float BAYER[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
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

vec3 nearest(vec3 c) {
	vec3 lab = oklab(c);
	int best = 0;
	float best_d = 1e9;
	for (int i = 0; i < PALETTE_SIZE; i++) {
		vec3 d = PALETTE_LAB[i] - lab;
		float dist = dot(d, d);
		if (dist < best_d) {
			best_d = dist;
			best = i;
		}
	}
	return PALETTE[best];
}

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 grid = vec2(floor(pixel_height * screen_px.x / screen_px.y + 0.5), pixel_height);
	vec2 cell = floor(SCREEN_UV * grid);
	vec2 cell_size = 1.0 / grid;
	// Promedio de 4 muestras dentro de la celda.
	vec2 base = cell * cell_size;
	vec3 c = (texture(screen_tex, base + cell_size * vec2(0.25, 0.25)).rgb
		+ texture(screen_tex, base + cell_size * vec2(0.75, 0.25)).rgb
		+ texture(screen_tex, base + cell_size * vec2(0.25, 0.75)).rgb
		+ texture(screen_tex, base + cell_size * vec2(0.75, 0.75)).rgb) * 0.25;
	if (dither) {
		ivec2 b = ivec2(mod(cell, 4.0));
		float t = (BAYER[b.y * 4 + b.x] + 0.5) / 16.0 - 0.5;
		c += t * dither_strength;
	}
	COLOR = vec4(nearest(clamp(c, 0.0, 1.0)), 1.0);
}
