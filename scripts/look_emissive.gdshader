shader_type canvas_item;
render_mode blend_add, unshaded;

// Pre-blurred halo sprites. Unshaded so a PointLight2D does not light the glow
// a second time. `lift` counters CanvasModulate when these sit on the world canvas.
uniform vec3 lift = vec3(1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb * lift, tex.a);
}
