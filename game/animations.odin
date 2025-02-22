package game

import "core:math/linalg"

SmoothStepAnimation :: struct {
    start_position: Vec2,
    end_position:   Vec2,
    duration:       f32,
    progress:       f32,
}

ssa_finished :: proc(ssa: ^SmoothStepAnimation) -> bool {
    return ssa.duration <= ssa.progress
}

ssa_update :: proc(ssa: ^SmoothStepAnimation, position: ^Vec2, dt: f32) -> bool {
    p := ssa.progress / ssa.duration
    t := p * p * (3.0 - 2.0 * p)
    position^ = linalg.lerp(ssa.start_position, ssa.end_position, t)
    ssa.progress += dt
    return ssa.duration <= ssa.progress
}
