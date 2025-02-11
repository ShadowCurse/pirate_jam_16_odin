package platform

InputState :: struct {
    quit:                 bool,
    lmb:                  KeyState,
    rmb:                  KeyState,
    space:                KeyState,
    mouse_screen_positon: [2]i32,
    mouse_delta:          [2]i32,
}

KeyState :: enum {
    NotPressed,
    Pressed,
    Released,
}

input_state_reset :: proc(input_state: ^InputState) {
  input_state.lmb = .NotPressed
  input_state.rmb = .NotPressed
  input_state.space = .NotPressed
  input_state.mouse_delta = {}
}
