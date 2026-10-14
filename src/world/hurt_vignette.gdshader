shader_type canvas_item;
// V3: a dark red edge when you're hurt. ViewFeel sets strength (0 = invisible).

uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 d = UV - vec2(0.5);
	d.x *= 1.6; // wider than tall, like the screen
	float edge = smoothstep(0.35, 0.95, length(d));
	COLOR = vec4(0.45, 0.0, 0.0, edge * strength * 0.85);
}
