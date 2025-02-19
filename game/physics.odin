package game

import "core:math/linalg"

ColliderRectangle :: struct {
    size: Vec2,
}

ColliderCircle :: struct {
    radius: f32,
}

PhysicsBody :: struct {
    acceleration: Vec2,
    velocity:     Vec2,
    position:     Vec2,
    friction:     f32,
    restitution:  f32,
    inv_mass:     f32,
}

Collision :: struct {
    position: Vec2,
    normal:   Vec2,
}

collision_circle_rectangle :: proc(
    circle: ColliderCircle,
    circle_position: Vec2,
    rectangle: ColliderRectangle,
    rectangle_position: Vec2,
) -> (
    Collision,
    bool,
) {
    rectangle_left := rectangle_position.x - rectangle.size.x / 2
    rectangle_right := rectangle_position.x + rectangle.size.x / 2
    rectangle_top := rectangle_position.y - rectangle.size.y / 2
    rectangle_bottom := rectangle_position.y + rectangle.size.y / 2
    p := Vec2 {
        min(max(circle_position.x, rectangle_left), rectangle_right),
        min(max(circle_position.y, rectangle_top), rectangle_bottom),
    }

    p_to_circle := circle_position - p
    if linalg.length2(p_to_circle) < circle.radius * circle.radius {
        normal := circle_position - p
        if (rectangle_left < p.x &&
               p.x < rectangle_right &&
               rectangle_top < p.y &&
               p.y < rectangle_bottom) {
            distance_left := p.x - rectangle_left
            distance_right := rectangle_right - p.x
            distance_top := p.y - rectangle_top
            distance_bottom := rectangle_bottom - p.y
            m := min(distance_left, distance_right, distance_top, distance_bottom)
            switch {
            case m == distance_left:
                p.x = rectangle_left
            case m == distance_right:
                p.x = rectangle_right
            case m == distance_top:
                p.y = rectangle_top
            case m == distance_bottom:
                p.y = rectangle_bottom
            }
            normal = p - circle_position
        }
        normal = linalg.normalize(normal)
        return {p, normal}, true
    }
    return {}, false
}

collision_circle_circle :: proc(
    circle1: ColliderCircle,
    circle1_position: Vec2,
    circle2: ColliderCircle,
    circle2_position: Vec2,
) -> (
    Collision,
    bool,
) {
    to_circle1 := circle1_position - circle2_position
    distance := linalg.length(to_circle1)
    if distance < circle1.radius + circle2.radius {
        to_circle1_norm := linalg.normalize(to_circle1)
        p := circle2_position + to_circle1_norm * circle2.radius
        normal := to_circle1_norm
        return {p, normal}, true

    }
    return {}, false
}

resolve_ball_border_collision :: proc(ball_body: ^PhysicsBody, collision: ^Collision) {
    contact_velocity := linalg.dot(ball_body.velocity, collision.normal)
    // If velocities are already in opposite directions,
    // do nothing
    if 0 < contact_velocity do return

    impulse_magnitude := -(1.0 + ball_body.restitution) * contact_velocity / ball_body.inv_mass
    impulse := collision.normal * impulse_magnitude
    ball_body.velocity += impulse * ball_body.inv_mass
}

resolve_ball_ball_collision :: proc(
    ball1: ^PhysicsBody,
    ball2: ^PhysicsBody,
    collision: ^Collision,
) {
    relative_velocity := ball1.velocity - ball2.velocity
    contact_velocity := linalg.dot(relative_velocity, collision.normal)
    // If velocities are already in opposite directions,
    // do nothing
    if 0 < contact_velocity do return

    min_restitution := min(ball1.restitution, ball2.restitution)
    impulse_magnitude :=
        -(1.0 + min_restitution) * contact_velocity / (ball1.inv_mass + ball2.inv_mass)
    impulse := collision.normal * impulse_magnitude

    ball1.velocity = ball1.velocity + impulse * ball1.inv_mass
    ball2.velocity = ball2.velocity + -impulse * ball2.inv_mass
}

physics_body_move :: proc(body: ^PhysicsBody, dt: f32) {
    body.acceleration = -body.velocity * body.friction
    body.position = body.position + body.velocity * dt + body.acceleration * 0.5 * dt * dt
    body.velocity += body.acceleration * dt
}

CollisionInfo :: struct {
    ball_idx:   u32,
    other_type: enum {
        Ball,
        Border,
    },
    other_idx:  u32,
    collision:  Collision,
}

process_physics :: proc(
    ball_colliders: []ColliderCircle,
    ball_bodies: []PhysicsBody,
    border_colliders: []ColliderRectangle,
    border_positions: []Vec2,
    dt: f32,
) {
    dt := dt / 4
    for _ in 0 ..< 4 {
        for &body in ball_bodies {
            physics_body_move(&body, dt)

            if linalg.length2(body.velocity) < 0.1 {
                body.velocity = {}
            }
        }

        collision_infos, _ := make(
            [dynamic]CollisionInfo,
            0,
            len(border_colliders) * len(ball_colliders) * len(ball_colliders),
            allocator = context.temp_allocator,
        )
        for i in 0 ..< len(ball_colliders) {
            ball_collider := ball_colliders[i]
            ball_body := ball_bodies[i]
            for j in i + 1 ..< len(ball_colliders) {
                ball2_collider := ball_colliders[j]
                ball2_body := ball_bodies[j]

                collision, hit := collision_circle_circle(
                    ball_collider,
                    ball_body.position,
                    ball2_collider,
                    ball2_body.position,
                )
                if hit {
                    append(
                        &collision_infos,
                        CollisionInfo{cast(u32)i, .Ball, cast(u32)j, collision},
                    )
                }
            }
            for j in 0 ..< len(border_colliders) {
                border_collider := border_colliders[j]
                border_position := border_positions[j]
                collision, hit := collision_circle_rectangle(
                    ball_collider,
                    ball_body.position,
                    border_collider,
                    border_position,
                )
                if hit do append(&collision_infos, CollisionInfo{cast(u32)i, .Border, 0, collision})
            }
        }
        for &info in collision_infos {
            ball_body := &ball_bodies[info.ball_idx]
            switch info.other_type {
            case .Ball:
                ball2_body := &ball_bodies[info.other_idx]
                resolve_ball_ball_collision(ball_body, ball2_body, &info.collision)
            case .Border:
                resolve_ball_border_collision(ball_body, &info.collision)
            }
        }
    }
}
