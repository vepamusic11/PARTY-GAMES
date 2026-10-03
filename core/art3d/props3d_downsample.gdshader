// Achica el render supermuestreado de las piezas 3D (Props3DBaker) sin
// bordes sucios.
//
// Concepto: *supermuestreo con alfa bien promediado*. Las piezas se
// renderizan `factor` veces más grandes y cada píxel final es el promedio de
// factor × factor píxeles. Si se promediara el color tal cual, los píxeles
// transparentes (negros) oscurecerían el borde: un borde mitad pieza y mitad
// vacío quedaría gris oscuro y semitransparente (doble oscurecimiento al
// dibujarlo). Acá el color se promedia pesado por su alfa y el alfa aparte:
// el borde queda del color de la pieza con la mitad de opacidad.
// Ejemplo (factor 2): 2 píxeles de tinta (alfa 1) y 2 vacíos (alfa 0)
// -> color = tinta, alfa = 0,5 (y no color = tinta/2, alfa = 0,5).
//
// Donde no hay nada, el color queda `fill_color` (la tinta) con alfa 0: los
// mipmaps (promedios más chicos) tampoco se ensucian con negro.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform int factor = 4;
uniform vec3 fill_color : source_color = vec3(0.11, 0.13, 0.25);

void fragment() {
	ivec2 src = textureSize(TEXTURE, 0);
	ivec2 base = ivec2(floor(UV * vec2(src) / float(factor))) * factor;
	vec3 rgb = vec3(0.0);
	float a = 0.0;
	for (int y = 0; y < factor; y++) {
		for (int x = 0; x < factor; x++) {
			vec4 c = texelFetch(TEXTURE, clamp(base + ivec2(x, y), ivec2(0), src - 1), 0);
			rgb += c.rgb * c.a;
			a += c.a;
		}
	}
	COLOR = vec4(a > 0.0 ? rgb / a : fill_color, a / float(factor * factor));
}
