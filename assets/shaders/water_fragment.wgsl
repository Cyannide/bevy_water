#import bevy_pbr::{
  pbr_functions::alpha_discard,
  pbr_fragment::pbr_input_from_standard_material,
  view_transformations::depth_ndc_to_view_z,
}

#ifdef PREPASS_PIPELINE
#import bevy_pbr::{
  prepass_io::{VertexOutput, FragmentOutput},
  pbr_deferred_functions::deferred_output,
}
#else
#import bevy_pbr::{
  forward_io::{VertexOutput, FragmentOutput},
  pbr_functions,
  pbr_functions::{apply_pbr_lighting, main_pass_post_lighting_processing},
  pbr_types::STANDARD_MATERIAL_FLAGS_FOG_ENABLED_BIT,
  pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
}
#endif

#ifdef MESHLET_MESH_MATERIAL_PASS
#import bevy_pbr::meshlet_visibility_buffer_resolve::resolve_vertex_output
#endif

#import bevy_water::water_bindings
#import bevy_water::water_functions as water_fn

@fragment
fn fragment(
#ifdef MESHLET_MESH_MATERIAL_PASS
    @builtin(position) frag_coord: vec4<f32>,
#else
  p_in: VertexOutput,
  @builtin(front_facing) is_front: bool,
#endif
) -> FragmentOutput {
#ifdef MESHLET_MESH_MATERIAL_PASS
  let p_in = resolve_vertex_output(frag_coord);
  let is_front = true;
#endif

  var in = p_in;
  var world_position: vec4<f32> = in.world_position;
  let w_pos = water_fn::uv_to_coord(in.uv);
  // Calculate normal.
  let height = water_fn::get_wave_height(w_pos);
#if QUALITY > 2
  let delta = 0.5;
  let height_dx = water_fn::get_wave_height(w_pos + vec2<f32>(delta, 0.0));
  let height_dz = water_fn::get_wave_height(w_pos + vec2<f32>(0.0, delta));
  in.world_normal = normalize(vec3<f32>(height - height_dx, delta, height - height_dz));
#else
  let pos = world_position.xyz + (in.world_normal * height);
  let pos_dx = dpdx(pos);
  let pos_dy = dpdy(pos);
  in.world_normal = normalize(cross(pos_dy, pos_dx));
#endif
 
  // If we're in the crossfade section of a visibility range, conditionally
  // discard the fragment according to the visibility pattern.
#ifdef VISIBILITY_RANGE_DITHER
  pbr_functions::visibility_range_dither(in.position, in.visibility_range_dither);
#endif

  // generate a PbrInput struct from the StandardMaterial bindings
  var pbr_input = pbr_input_from_standard_material(in, is_front);

  let deep_color = water_bindings::material.deep_color;
  var water_color = deep_color;
#ifdef DEPTH_PREPASS
#ifndef PREPASS_PIPELINE
#ifndef WEBGL2
  let water_clarity = water_bindings::material.clarity;
  let shallow_color = water_bindings::material.shallow_color;
  let edge_scale = water_bindings::material.edge_scale;
  let edge_color = water_bindings::material.edge_color;

  let z_depth_buffer_ndc = bevy_pbr::prepass_utils::prepass_depth(in.position, 0u);
  var z_depth_buffer_view = depth_ndc_to_view_z(z_depth_buffer_ndc);
  // Cleared depth (reversed-Z: 0.0) means NOTHING opaque behind this water —
  // past the terrain's streaming radius, or open sky under the horizon. The
  // raw math then yields depth_diff <= 0, the shore smoothstep reads that as
  // "touching ground", and the whole far ocean gets painted edge_color
  // (default white) — a bright plateau no fog can fully bury. No ground at
  // all is the *deepest* water, not the shallowest: force the far case.
  if (z_depth_buffer_ndc <= 0.0) {
    z_depth_buffer_view = -1.0e9;
  }
  let z_fragment_view = depth_ndc_to_view_z(in.position.z);
  let depth_diff_view = z_fragment_view - z_depth_buffer_view;
  let beers_law = exp(-depth_diff_view * water_clarity);
  let depth_color = vec4<f32>(mix(deep_color.xyz, shallow_color.xyz, beers_law), 1.0 - beers_law);
  water_color = mix(edge_color, depth_color, smoothstep(0.0, edge_scale, depth_diff_view));
#endif
#endif
#endif
  pbr_input.material.base_color *= water_color;

  //let foam_color = water_bindings::material.edge_color;
  //let foam = mix(foam_color, depth_color, smoothstep(0.0, edge_scale, depth_diff_view));

  // alpha discard
  pbr_input.material.base_color = alpha_discard(pbr_input.material, pbr_input.material.base_color);

#ifdef PREPASS_PIPELINE
  // write the gbuffer, lighting pass id, and optionally normal and motion_vector textures
  let out = deferred_output(in, pbr_input);
#else
  // in forward mode, we calculate the lit color immediately, and then apply some post-lighting effects here.
  // in deferred mode the lit color and these effects will be calculated in the deferred lighting shader
  var out: FragmentOutput;
  if (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_UNLIT_BIT) == 0u {
    out.color = apply_pbr_lighting(pbr_input);
  } else {
    out.color = pbr_input.material.base_color;
  }

  // apply in-shader post processing (fog, alpha-premultiply, and also tonemapping, debanding if the camera is non-hdr)
  // note this does not include fullscreen postprocessing effects like bloom.
  //
  // Dissolve the water before its own grid edge: alpha fades to zero over the
  // last stretch, so the silhouette of the finite tile grid can never be seen
  // against the sky — a vanished pixel IS the background, exactly, with no
  // dependence on fog, tonemapping or blend-order being colour-identical
  // (three separate near-misses taught us not to depend on that). Numbers
  // assume a grid whose nearest edge is >= ~896 units from the camera.
  let camera_distance = length(in.world_position.xyz - bevy_pbr::mesh_view_bindings::view.world_position.xyz);
  out.color.a *= 1.0 - smoothstep(700.0, 860.0, camera_distance);

  // Global reveal/fade knob, 1.0 in normal play. Qualified: `material` only
  // exists in this file through the bindings module.
  out.color.a *= water_bindings::material.fade;

  // The fog bit is forced rather than trusted: `fog_enabled` defaults to true
  // on the base StandardMaterial, yet the flag was observably absent at the
  // gate here — terrain forcing the same bit fogged while this shader did
  // not. Until the flag's journey through the extended-material uniform is
  // understood, assert the intent.
  pbr_input.material.flags |= STANDARD_MATERIAL_FLAGS_FOG_ENABLED_BIT;
  out.color = main_pass_post_lighting_processing(pbr_input, out.color);

  // show grid
  // 3.938... = WATER_SIZE / ((WATER_SIZE / 4) + 1)
  //let f_pos = step(fract((w_pos / 3.9384615384615)), vec2<f32>(0.995));
  //let grid = step(f_pos.x + f_pos.y, 1.00);
  //out.color += vec4<f32>(grid, grid, grid, 0.00);
#endif

  return out;
}
