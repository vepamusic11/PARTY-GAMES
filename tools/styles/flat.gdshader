// Estilo "flat": minimalista moderno como post-proceso (exploración, ver
// docs/ESTILOS.md). Es una APROXIMACIÓN: lo que define al flat (sin relieve
// en los botones, más aire entre elementos) es geometría y se cambia en
// UiTheme, no con un filtro. Lo que sí se puede hacer sobre la imagen:
// 1. Cielo liso: el degradé celeste (y las sombras que caen sobre él) se
//    reemplaza por un único color plano.
// 2. Sin relieve "de juguete": el borde inferior de botones, tarjetas y
//    podios es el mismo color oscurecido un 18–25 % (UiTheme.button_style).
//    Si un píxel es exactamente eso respecto del que tiene 8 o 16 px arriba,
//    toma el color de arriba y el relieve desaparece.
// 3. Colores un poco más claros y menos saturados (paleta pastel moderna).
// Se probó también afinar los contornos de tinta (reemplazarlos por el color
// vecino), pero se comía el texto oscuro de los botones amarillos y los
// números de los marcadores: se descartó.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 flat_sky : source_color = vec3(0.604, 0.812, 0.965); // #9ACFF6
uniform float soften = 0.12;

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

// 1 si el color es el cielo (celeste de tono ~-120° en OKLab), 0 si no.
float sky_mask(vec3 lab) {
	float chroma = length(lab.yz);
	float hue = degrees(atan(lab.z, lab.y));
	return (1.0 - smoothstep(6.0, 10.0, abs(hue + 120.0)))
		* smoothstep(0.02, 0.04, chroma) * (1.0 - smoothstep(0.136, 0.145, chroma))
		* smoothstep(0.5, 0.62, lab.x);
}

vec3 flatten(vec3 c) {
	vec3 lab = oklab(c);
	c = mix(c, flat_sky, sky_mask(lab));
	// Pastel: un poco hacia el blanco y hacia el gris.
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), soften * 0.8);
	return mix(c, vec3(1.0), soften * 0.5 * step(0.35, l));
}

// Si `c` es `above` oscurecido un 12–32 % (mismo tono), devuelve `above`.
vec3 unbevel(vec3 c, vec3 above) {
	float k = dot(c, above) / max(dot(above, above), 1e-4);
	bool same_hue = length(c - above * k) < 0.035;
	bool bevel = same_hue && k > 0.68 && k < 0.88 && length(above) > 0.6;
	return bevel ? above : c;
}

void fragment() {
	vec2 d = vec2(0.0, 8.0 / 1080.0);  // 8 px de una pantalla 1080p, en UV.
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c = unbevel(c, texture(screen_tex, SCREEN_UV - d).rgb);
	c = unbevel(c, texture(screen_tex, SCREEN_UV - 2.0 * d).rgb);
	COLOR = vec4(flatten(c), 1.0);
}
