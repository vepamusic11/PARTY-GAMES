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
// sea cual sea la resolución a la que se renderiza (3 u, como en 2D).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec3 ink : source_color = vec3(0.11, 0.13, 0.25);
uniform float width = 0.3;  // En unidades del mundo (0,1 = 1 u de PlayerAvatar).

void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	float l = length(n.xy);
	vec2 dir = l > 1e-4 ? n.xy / l : vec2(0.0);
	p.xy += dir * width;
	p.z -= width;  // Un poco hacia atrás: no tapa piezas que están delante.
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	ALBEDO = ink;
}
