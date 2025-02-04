package game

InputState :: struct {
    quit:                 bool,
    lmb:                  KeyState,
    rmb:                  KeyState,
    space:                KeyState,
    mouse_screen_positon: Vec2i32,
    mouse_delta:          Vec2i32,
}

KeyState :: enum {
    NotPressed,
    Pressed,
    Released,
}

input_state_reset_keys :: proc(input_state: ^InputState) {
  input_state.lmb = .NotPressed
  input_state.rmb = .NotPressed
  input_state.space = .NotPressed
}
