// Plástico de juguete para las mascotas 3D (ver docs/ARTE.md).
//
// No usa las luces de la escena: la "luz de estudio" (principal, relleno,
// contraluz y rebote del piso) está dentro del shader, fija respecto de la
// cámara. Así cuesta una sola pasada por pieza en cualquier renderer
// (en Compatibility cada luz real extra es otra pasada de dibujo) y la
// mascota se ve igual en la TV, en la hoja y en el celular.
//
// Conceptos:
// - Rampa de color (como MascotShading en 2D): sombra -> color -> luz, con
//   colores elegidos desde el color del jugador (no solo "más oscuro").
// - Brillo especular: el reflejo chico y blanco de la luz principal. Con
//   `spec_power` alto queda chico y nítido, como plástico lustrado.
// - "Clearcoat" falso (`coat_strength`): un segundo brillo, ancho y suave,
//   como la capa de barniz transparente de un juguete o un auto.
// - Rim light (contraluz): una línea de luz en el borde, del lado opuesto a
//   la luz principal. Despega la silueta del fondo, sobre todo en negro.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;

uniform vec3 low_color : source_color = vec3(0.3);
uniform vec3 mid_color : source_color = vec3(0.6);
uniform vec3 high_color : source_color = vec3(0.9);
uniform vec3 bounce_color : source_color = vec3(0.7);
uniform float bounce_strength = 0.35;
uniform vec3 rim_color : source_color = vec3(1.0);
uniform float rim_strength = 0.3;
uniform float spec_strength = 0.9;
uniform float spec_power = 120.0;
uniform float coat_strength = 0.18;
uniform float coat_power = 10.0;
uniform vec3 edge_color : source_color = vec3(0.5);
uniform float edge_strength = 0.0;  // Cara: el borde se oscurece (queda "metida" en la capucha).

// Direcciones en el espacio de la cámara (x derecha, y arriba, z hacia la cámara).
const vec3 LIGHT_KEY = vec3(-0.5, 0.85, 0.3);     // Principal: arriba a la izquierda.
const vec3 LIGHT_FILL = vec3(0.75, 0.05, 0.66);    // Relleno: derecha, suave.
const vec3 LIGHT_RIM = vec3(0.62, 0.55, -0.56);    // Contraluz: atrás a la derecha.

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 key = normalize(LIGHT_KEY);
	float d = dot(n, key);
	vec3 col = d < 0.3
		? mix(low_color, mid_color, smoothstep(-0.45, 0.3, d))
		: mix(mid_color, high_color, smoothstep(0.45, 1.0, d));
	// Relleno: levanta un poco la sombra del lado derecho.
	float fill = max(dot(n, normalize(LIGHT_FILL)), 0.0);
	col = mix(col, mid_color, fill * 0.3 * (1.0 - smoothstep(0.1, 0.6, d)));
	// Rebote del piso: las caras que miran abajo reciben luz clara.
	col = mix(col, bounce_color, smoothstep(-0.15, -0.9, n.y) * bounce_strength);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.5);
	col = mix(col, edge_color, edge_strength * smoothstep(0.15, 0.85, 1.0 - ndv));
	// Contraluz: solo en el borde y del lado de la luz de atrás.
	vec2 side = normalize(n.xy + vec2(1e-4));
	float rim = fres * smoothstep(-0.1, 0.7, dot(side, normalize(LIGHT_RIM.xy)));
	col += rim_color * rim * rim_strength;
	// Brillos: uno chico y nítido (especular) y uno ancho (barniz).
	vec3 h = normalize(key + v);
	float nh = max(dot(n, h), 0.0);
	float spec = smoothstep(0.25, 0.75, pow(nh, spec_power));
	float coat = pow(nh, coat_power);
	col += vec3(spec * spec_strength + coat * coat_strength);
	ALBEDO = col;
}
