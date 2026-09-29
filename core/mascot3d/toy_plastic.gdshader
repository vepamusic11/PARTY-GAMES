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
//   colores elegidos desde el color del jugador (no solo "más oscuro"): la
//   sombra es más saturada y fría, la luz más clara y cálida.
// - Brillo especular "pintado": el reflejo de la luz principal recortado
//   con un borde nítido (como lo pinta un ilustrador), un poco estirado
//   siguiendo la curva de la pieza. Ejemplo: la mancha blanca alargada
//   arriba a la izquierda de la cabeza.
// - "Clearcoat" falso (`coat_strength`): un segundo brillo, ancho y suave,
//   como la capa de barniz transparente de un juguete o un auto.
// - Borde profundo (`edge_*`): hacia la silueta el color se vuelve más
//   oscuro y saturado, como el plástico que se ve "de canto".
// - Rim light (contraluz): una línea de luz celeste en el borde, abajo a la
//   derecha. Despega la silueta del fondo, sobre todo en negro.
// - Reflejo del cielo (`sky_strength`): una banda clara y nítida cerca del
//   borde de abajo a la derecha, como el reflejo de una ventana.
// - Cara pintada en la cabeza (`face_on`): la cara blanca no es otra malla
//   sino una zona de la misma cabeza (una elipse vista de frente). Así el
//   borde es limpio a cualquier tamaño (sin dos superficies que se cruzan)
//   y tiene la sombra de la "capucha" arriba y un labio de luz afuera.
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
uniform float spec_size = 0.05;      // Tamaño del reflejo nítido (0 = nada; 0,05 ≈ 18°).
uniform float spec_stretch = 1.35;   // > 1: el reflejo se estira en diagonal, siguiendo la curva.
// Borde del reflejo nítido: 0,012 es un corte "pintado"; más grande, un
// reflejo "jugoso" que se funde con el color (el de la maqueta: ~0,05).
uniform float spec_soft = 0.012;
// Cuánto se ensancha la zona de sombra de la rampa (0 = la de siempre: corta,
// de juguete plano; 1 = el volumen de esfera de la maqueta: la sombra sube
// hasta la mitad de la pieza y el color pleno queda arriba a la izquierda).
uniform float shade_spread = 0.0;
uniform float coat_strength = 0.18;
uniform float coat_power = 10.0;
uniform vec3 edge_color : source_color = vec3(0.5);
uniform float edge_strength = 0.0;
uniform vec2 edge_range = vec2(0.3, 0.95);  // Desde / hasta qué "canto" (1 - N·V) llega al color del borde.
uniform float sky_strength = 0.0;
uniform float glow = 0.0;            // Gema y foco: el centro brilla (sin sombra).
// Sombra de la cabeza sobre el cuerpo (oclusión "pintada"): desde neck_y
// hacia arriba (en unidades de la pieza) el color baja a la sombra.
// Ejemplo: el cuerpo se oscurece justo debajo del mentón, como en la maqueta.
uniform float neck_shadow = 0.0;
uniform float neck_y = 0.0;

// Cara pintada (solo la cabeza). VERTEX es la esfera unidad: face_scale
// (semiejes de la cabeza) la lleva a unidades de la mascota.
uniform float face_on = 0.0;
uniform vec3 face_scale = vec3(1.0);
uniform vec2 face_center = vec2(0.0);
uniform vec2 face_radii = vec2(1.0);
uniform vec3 face_low : source_color = vec3(0.78);
uniform vec3 face_mid : source_color = vec3(0.95);
uniform vec3 face_high : source_color = vec3(1.0);

// Direcciones en el espacio de la cámara (x derecha, y arriba, z hacia la cámara).
const vec3 LIGHT_KEY = vec3(-0.5, 0.85, 0.42);     // Principal: arriba a la izquierda.
const vec3 LIGHT_FILL = vec3(0.75, 0.05, 0.66);    // Relleno: derecha, suave.
const vec2 RIM_SIDE = vec2(0.72, -0.69);           // Contraluz y cielo: abajo a la derecha.

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX * face_scale;
}

// Rampa de tres colores con transiciones suaves pero cortas (más "juguete"
// que un degradé lineal). t: 0 sombra, 1 luz.
vec3 ramp(vec3 lo, vec3 mi, vec3 hi, float t) {
	float a = mix(0.1, -0.2, shade_spread);   // Desde dónde empieza a aclararse la sombra…
	float b = mix(0.5, 0.64, shade_spread);   // …y dónde llega al color pleno.
	return t < b
		? mix(lo, mi, smoothstep(a, b, t))
		: mix(mi, hi, smoothstep(0.82, 1.0, t));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 key = normalize(LIGHT_KEY);
	float d = dot(n, key);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fres = 1.0 - ndv;
	float t = d * 0.5 + 0.5;
	vec3 col = ramp(low_color, mid_color, high_color, t);
	// Relleno: levanta un poco la sombra del lado derecho.
	float fill = max(dot(n, normalize(LIGHT_FILL)), 0.0);
	col = mix(col, mid_color, fill * 0.28 * (1.0 - smoothstep(0.1, 0.6, d)));
	// Volumen de esfera (shade_spread): la mitad de abajo de la pieza queda en
	// una sombra graduada aunque el relleno la alcance, como el mentón de la
	// capucha y la panza de la maqueta.
	col = mix(col, low_color, shade_spread * 0.5 * smoothstep(0.2, -0.75, n.y));
	// Rebote del piso: las caras que miran abajo reciben luz clara.
	col = mix(col, bounce_color, smoothstep(-0.2, -0.95, n.y) * bounce_strength);
	// Sombra de la cabeza (cuerpo): más fuerte cuanto más arriba.
	col = mix(col, low_color, neck_shadow * smoothstep(neck_y - 0.45, neck_y + 0.25, local_pos.y));
	// Borde profundo: hacia la silueta, más oscuro y saturado.
	col = mix(col, edge_color, edge_strength * smoothstep(edge_range.x, edge_range.y, fres));

	float spec_k = spec_strength;
	float coat_k = coat_strength;
	float rim_k = rim_strength;
	float sky_k = sky_strength;
	if (face_on > 0.5) {
		vec2 q = (local_pos.xy - face_center) / face_radii;
		float e = length(q);
		float aa = max(fwidth(e), 1e-4) * 0.8;
		float front = smoothstep(-0.05, 0.25, local_pos.z);
		float face = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, e)) * front;
		// Cara: blanca y mate, con la sombra de la capucha en el borde (más arriba que abajo).
		vec3 fcol = ramp(face_low, face_mid, face_high, t * 0.7 + 0.3);
		float up = clamp(q.y * 0.6 + 0.5, 0.0, 1.0);
		fcol = mix(fcol, face_low, smoothstep(0.7, 1.0, e) * mix(0.35, 0.95, up));
		// Labio de la capucha: justo afuera de la cara, una línea más oscura y
		// después un brillo fino arriba (el borde de plástico que recibe la luz).
		float out_e = e - 1.0;
		float lip_dark = (1.0 - smoothstep(0.0, 0.07 + aa, out_e)) * front;
		float lip_light = smoothstep(0.05, 0.1, out_e) * (1.0 - smoothstep(0.12, 0.2, out_e)) * up * front;
		col = mix(col, low_color, lip_dark * 0.55);
		col = mix(col, high_color, lip_light * 0.5);
		col = mix(col, fcol, face);
		spec_k = mix(spec_k, 0.0, face);
		coat_k = mix(coat_k, coat_k * 0.35, face);
		rim_k = mix(rim_k, 0.0, face);
		sky_k = mix(sky_k, 0.0, face);
	}

	// Contraluz: solo en el borde y del lado de la luz de atrás.
	vec2 side = normalize(n.xy + vec2(1e-4));
	float side_k = smoothstep(-0.1, 0.8, dot(side, RIM_SIDE));
	col += rim_color * pow(fres, 3.0) * side_k * rim_k;
	// Reflejo del cielo: banda nítida pegada al borde de abajo a la derecha.
	float band = smoothstep(0.55, 0.62, fres) * (1.0 - smoothstep(0.8, 0.88, fres));
	col = mix(col, vec3(1.0), band * smoothstep(0.35, 0.9, dot(side, RIM_SIDE)) * sky_k);
	// Brillos: uno ancho (barniz) y uno nítido y estirado ("pintado").
	vec3 h = normalize(key + v);
	float nh = max(dot(n, h), 0.0);
	col += vec3(pow(nh, coat_power) * coat_k);
	vec3 hx = normalize(vec3(1.0, 1.0, 0.0));
	vec3 ns = normalize(n - hx * dot(n - h, hx) * (1.0 - 1.0 / spec_stretch));
	float cut = 1.0 - spec_size;
	float spec = smoothstep(cut, cut + spec_soft, dot(ns, h));
	col = mix(col, vec3(1.0), spec * spec_k);
	// Gema / foco: centro blanco caliente que no depende de la luz.
	col = mix(col, high_color, glow * smoothstep(0.55, 1.0, ndv));
	ALBEDO = clamp(col, 0.0, 1.0);
}
