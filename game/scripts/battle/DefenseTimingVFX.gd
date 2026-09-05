class_name DefenseTimingVFX
extends RefCounted
## 防御动作场固定粒子素材工厂。

static func make_particle_texture() -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 12
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var texture_gradient := Gradient.new()
	texture_gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	texture_gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.8),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	texture.gradient = texture_gradient
	return texture

static func create(parent: Node) -> Array[GPUParticles2D]:
	var texture := make_particle_texture()

	var trail := GPUParticles2D.new()
	trail.amount = 28
	trail.lifetime = 0.34
	trail.one_shot = true
	trail.explosiveness = 1.0
	trail.fixed_fps = 30
	trail.local_coords = false
	trail.visibility_rect = Rect2(-2200.0, -1400.0, 4400.0, 2800.0)
	trail.texture = texture
	trail.z_index = 121
	var trail_material := ParticleProcessMaterial.new()
	trail_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	trail_material.emission_box_extents = Vector3(16.0, 4.0, 1.0)
	trail_material.direction = Vector3(1.0, 0.0, 0.0)
	trail_material.spread = 24.0
	trail_material.initial_velocity_min = 28.0
	trail_material.initial_velocity_max = 92.0
	trail_material.gravity = Vector3.ZERO
	trail_material.damping_min = 4.0
	trail_material.damping_max = 8.0
	trail_material.scale_min = 0.35
	trail_material.scale_max = 0.85
	trail.process_material = trail_material
	parent.add_child(trail)

	var impact := GPUParticles2D.new()
	impact.amount = 18
	impact.lifetime = 0.42
	impact.one_shot = true
	impact.explosiveness = 1.0
	impact.fixed_fps = 30
	impact.local_coords = false
	impact.visibility_rect = Rect2(-320.0, -320.0, 640.0, 640.0)
	impact.texture = texture
	impact.z_index = 122
	var impact_material := ParticleProcessMaterial.new()
	impact_material.direction = Vector3(0.0, -1.0, 0.0)
	impact_material.spread = 180.0
	impact_material.initial_velocity_min = 90.0
	impact_material.initial_velocity_max = 210.0
	impact_material.gravity = Vector3(0.0, 180.0, 0.0)
	impact_material.damping_min = 3.0
	impact_material.damping_max = 7.0
	impact_material.scale_min = 0.4
	impact_material.scale_max = 1.0
	impact.process_material = impact_material
	parent.add_child(impact)
	var particles: Array[GPUParticles2D] = [trail, impact]
	return particles
