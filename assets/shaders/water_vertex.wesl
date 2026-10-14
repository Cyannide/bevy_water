import bevy_pbr::render::{
	mesh_functions,
	skinning,
	view_transformations::position_world_to_clip,
};

import bevy_water::water_functions as water_fn;

@if(PREPASS_PIPELINE)
import bevy_pbr::prepass::io::{Vertex, VertexOutput, decompress_vertex};
@else
import bevy_pbr::render::forward_io::{Vertex, VertexOutput, decompress_vertex};

@vertex
fn vertex(vertex_in: Vertex) -> VertexOutput {
  var out: VertexOutput;
  // Bevy 0.20 may store a mesh's attributes compressed; read them through
  // its decompression, as its own mesh shader does.
  let vertex = decompress_vertex(vertex_in, vertex_in.instance_index);

@if(SKINNED)
  var model = skinning::skin_model(vertex.joint_indices, vertex.joint_weights, vertex_in.instance_index);
@else
  var model = mesh_functions::get_world_from_local(vertex_in.instance_index);

@if(VERTEX_UVS && SKINNED)
  out.world_normal = skinning::skin_normals(model, vertex.normal);
@if(VERTEX_UVS && !SKINNED)
  out.world_normal = mesh_functions::mesh_normal_local_to_world(
		vertex.normal,
		vertex_in.instance_index
	);

  let world_position = mesh_functions::mesh_position_local_to_world(model, vec4<f32>(vertex.position, 1.0));

  // Add the wave height to the world position.
	var height = -0.5;
@if(QUALITY__GE_3) {
  let w_pos = water_fn::uv_to_coord(vertex.uv);
  height = water_fn::get_wave_height(w_pos);
}

  out.world_position = world_position + vec4<f32>((out.world_normal * height), 0.);
  out.position = position_world_to_clip(out.world_position.xyz);

@if(VERTEX_UVS_A)
  out.uv = vertex.uv;

@if(VERTEX_TANGENTS)
  out.world_tangent = mesh_functions::mesh_tangent_local_to_world(
		model,
		vertex.tangent,
		vertex_in.instance_index
	);

@if(VERTEX_COLORS)
  out.color = vertex.color;

@if(VERTEX_OUTPUT_INSTANCE_INDEX)
	out.instance_index = vertex_in.instance_index;

  return out;
}
