#define_import_path bevy_water::water_bindings

struct WaterMaterial {
  deep_color: vec4<f32>,
  shallow_color: vec4<f32>,
  edge_color: vec4<f32>,
  coord_offset: vec2<f32>,
  coord_scale: vec2<f32>,
  amplitude: f32,
  clarity: f32,
  edge_scale: f32,
  wave_blend: f32,
  wave_dir_a: vec2<f32>,
  wave_dir_b: vec2<f32>,
  // LAST, matching WaterMaterialUniform: uniform layouts are positional, and
  // inserting this mid-struct once shifted every following field — the shader
  // read a wave direction as the fade and the entire ocean vanished.
  fade: f32,
};

@group(#{MATERIAL_BIND_GROUP}) @binding(100)
var<uniform> material: WaterMaterial;
