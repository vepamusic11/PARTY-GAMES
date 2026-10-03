// Contorno de tinta por "casco invertido" (inverted hull), ver docs/ARTE.md.
//
// Se dibuja la misma pieza una segunda vez, inflada hacia afuera y
// mostrando solo sus caras de atrás (cull_front), de color tinta. Lo que
// sobresale del borde de la pieza original es el contorno.
// Ejemplo: la cabeza roja se dibuja normal; atrás, una cabeza "un poquito
// más grande" azul oscuro. Solo se ve el anillo que asoma alrededor.
//
// El inflado se hace en el plano de la pantalla (x, y de la cámara) y en
// unidades del mundo: el contorno mide lo mismo en proporción a la mascota,
// sea cual sea la resolución a la que se renderiza.
//
// Trazo "con intención": un ilustrador engrosa la línea del lado de la
// sombra y la afina del lado de la luz. Acá el ancho varía con la
// dirección del borde: `weight` más grueso abajo a la derecha y más fino
// arriba a la izquierda (donde pega la luz principal).
// Ejemplo: con width 0,18 y weight 0,35, la línea mide ~0,12 arriba a la
// izquierda de la cabeza y ~0,24 abajo a la derecha.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec3 ink : source_color = vec3(0.11, 0.13, 0.25);
uniform float width = 0.18;   // En unidades del mundo (0,1 = 1 u de PlayerAvatar).
uniform float weight = 0.35;  // Cuánto cambia el ancho entre el lado de la luz y el de la sombra.
// Ancho mínimo en píxeles del render: de chica (juegos) la línea no se
// pierde. Ejemplo: celda de 116 px con supersampling 2× -> ~0,17 del mundo.
uniform float min_px = 2.6;

const vec2 SHADOW_SIDE = vec2(0.6, -0.8);

void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	float l = length(n.xy);
	vec2 dir = l > 1e-4 ? n.xy / l : vec2(0.0);
	// Tamaño de un píxel en unidades del mundo (cámara ortográfica).
	float px = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(width, min_px * px) * (1.0 + weight * dot(dir, SHADOW_SIDE));
	p.xy += dir * w;
	p.z -= width;  // Un poco hacia atrás: no tapa piezas que están delante.
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	ALBEDO = ink;
}
