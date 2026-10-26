shader_type canvas_item;
render_mode unshaded;

uniform sampler2D background_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 world_size = vec2(1.0);
uniform vec2 canvas_size = vec2(1.0);
uniform vec4 background_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
varying vec2 world_uv;

void vertex() {
	world_uv = VERTEX / canvas_size;
}

void fragment() {
	vec2 background_uv = background_uv_rect.xy + world_uv * background_uv_rect.zw;
	vec4 background = texture(background_texture, background_uv);
	vec2 detail_uv = world_uv * world_size / 640.0;
	detail_uv = 1.0 - abs(mod(detail_uv, vec2(2.0)) - vec2(1.0));
	vec4 detail = texture(detail_texture, detail_uv);
	vec2 edge = min(world_uv, vec2(1.0) - world_uv);
	float center_weight = smoothstep(0.08, 0.11, min(edge.x, edge.y));
	COLOR = mix(background, detail, center_weight) * tint;
}
