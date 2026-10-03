shader_type canvas_item;
// Desenfoque gaussiano de una sola pasada (7 × 7 muestras). PartyBackground
// lo usa UNA vez al preparar el escenario (y de nuevo solo si cambia el
// tamaño): no corre en cada frame, así que su costo no pesa en la TV.

uniform float step_px = 1.1;  // Separación entre muestras, en píxeles de la textura.

void fragment() {
	vec4 sum = vec4(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float w = exp(-float(x * x + y * y) / 5.0);
			sum += texture(TEXTURE, UV + vec2(float(x), float(y)) * TEXTURE_PIXEL_SIZE * step_px) * w;
			total += w;
		}
	}
	COLOR = vec4((sum / total).rgb, 1.0);
}
