shader_type canvas_item;
render_mode unshaded;

// One full-screen pass. hint_screen_texture is the single backbuffer copy.
// DoF is extra taps in this same pass (no second copy). Off unless dof_enabled > 0.5.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D grade_ramp : filter_linear, repeat_disable;
uniform float tint_strength = 0.25;
uniform float contrast = 1.06;
uniform float vignette_amt = 0.4;
uniform vec4 fog_color : source_color = vec4(0.55, 0.50, 0.42, 1.0);
uniform float fog_amount = 0.12;
uniform float protect = 0.45;
uniform float dof_enabled = 0.0;
uniform float dof_px = 7.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 src;
	if (dof_enabled > 0.5) {
		// Screen-Y tilt-shift: sharp mid band (the fight), soft toward the far edge
		// (top) and the near edge (bottom). HUD sits on a higher CanvasLayer, so it
		// is not in this texture.
		float y = uv.y;
		float dist = 0.0;
		if (y < 0.30) {
			dist = (0.30 - y) / 0.30;
		} else if (y > 0.74) {
			dist = (y - 0.74) / 0.26;
		}
		dist = smoothstep(0.0, 1.0, dist);
		vec2 px = SCREEN_PIXEL_SIZE * (dist * dof_px);
		src = texture(screen_texture, uv).rgb * 0.28;
		src += texture(screen_texture, uv + vec2(px.x, 0.0)).rgb * 0.12;
		src += texture(screen_texture, uv + vec2(-px.x, 0.0)).rgb * 0.12;
		src += texture(screen_texture, uv + vec2(0.0, px.y)).rgb * 0.12;
		src += texture(screen_texture, uv + vec2(0.0, -px.y)).rgb * 0.12;
		src += texture(screen_texture, uv + vec2(px.x, px.y)).rgb * 0.06;
		src += texture(screen_texture, uv + vec2(-px.x, px.y)).rgb * 0.06;
		src += texture(screen_texture, uv + vec2(px.x, -px.y)).rgb * 0.06;
		src += texture(screen_texture, uv + vec2(-px.x, -px.y)).rgb * 0.06;
	} else {
		src = texture(screen_texture, uv).rgb;
	}

	float l = dot(src, vec3(0.2126, 0.7152, 0.0722));
	float curved = clamp((l - 0.5) * contrast + 0.5, 0.0, 1.0);
	vec3 hue = src * (curved / max(l, 0.0008));
	vec3 tint = texture(grade_ramp, vec2(clamp(l, 0.001, 0.999), 0.5)).rgb;
	float shadow = 1.0 - smoothstep(0.10, 0.70, l);
	float mix_amt = tint_strength * mix(0.18, 1.0, shadow);
	vec3 graded = mix(hue, tint * max(curved, 0.12), mix_amt);
	// Bright pixels (lamps, muzzle, fire) keep their own hue so warm lights stay warm.
	float hi = smoothstep(0.52, 0.90, l);
	graded = mix(graded, src, hi * protect);
	float fog = smoothstep(0.58, 0.0, uv.y) * fog_amount * (1.0 - hi * 0.8);
	graded = mix(graded, fog_color.rgb, clamp(fog, 0.0, 1.0));
	vec2 q = uv - vec2(0.5);
	float vig = smoothstep(0.30, 0.90, length(q * vec2(1.08, 0.94)));
	graded *= 1.0 - vig * vignette_amt * (1.0 - hi * 0.4);
	COLOR = vec4(graded, 1.0);
}
