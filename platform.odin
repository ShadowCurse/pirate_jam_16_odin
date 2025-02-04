package platform

import "core:fmt"
import "core:slice"
import "game"
import "vendor:sdl2"

@(export = false)
main :: proc() {
    memory := game.memory_create()
    context.allocator = game.memory_perm_allocator(&memory)
    context.temp_allocator = game.memory_scatch_allocator(&memory)
    context.logger = game.logger_create()

    if sdl2.Init({.VIDEO}) != 0 {
        game.log_err("Could not init SDL2: %s", sdl2.GetError())
        return
    }
    defer sdl2.Quit()

    window := sdl2.CreateWindow("pirate_jam_odin", 0, 0, 1280, 720, {})
    if window == nil {
        game.log_err("Could not create SDL2 window: %s", sdl2.GetError())
        return
    }
    defer sdl2.DestroyWindow(window)
    sdl2.ShowWindow(window)
    surface := sdl2.GetWindowSurface(window)

    runtime: Runtime
    fn, err := runtime_load(&runtime)
    if err != nil {
        game.log_err("Could not load runtime: %", err)
    }

    game.log_info("Running the runtime")
    input_state: game.InputState = {}
    event: sdl2.Event = ---
    for {
        game.input_state_reset_keys(&input_state)
        for sdl2.PollEvent(&event) {
            input_state_update(&input_state, &event)
        }
        if input_state.quit do break
        pixels := slice.from_ptr(cast([^]u32)surface.pixels, 1280 * 720)
        fn(&memory, pixels, 1280, 720, &input_state)
        sdl2.UpdateWindowSurface(window)
    }
}

RuntimeFn :: #type proc(
    memory: ^game.Memory,
    pixels: []u32,
    width: u32,
    height: u32,
    input_state: ^game.InputState,
)
RUNTIME_LIB_PATH :: "game.so"
RUNTIM_EXPORT_NAME :: "runtime_main"
RTLD_NOW :: 0x00002

Runtime :: struct {
    handle: rawptr,
}

RuntimeError :: enum byte {
    None         = 0,
    NoRuntimeLib = 1,
    NoRuntimeFn  = 2,
}

import "core:os"

runtime_load :: proc(runtime: ^Runtime) -> (RuntimeFn, RuntimeError) {
    new_handle := os.dlopen(RUNTIME_LIB_PATH, RTLD_NOW)
    if new_handle == nil {
        return nil, .NoRuntimeLib
    }
    new_runtime := os.dlsym(new_handle, RUNTIM_EXPORT_NAME)
    if new_runtime == nil {
        os.dlclose(runtime.handle)
        return nil, .NoRuntimeFn
    }

    if runtime.handle != nil {
        os.dlclose(runtime.handle)
    }

    runtime.handle = new_handle
    return cast(RuntimeFn)new_runtime, nil
}

input_state_update :: proc(input_state: ^game.InputState, event: ^sdl2.Event) {
    #partial switch event.type {
    case sdl2.EventType.QUIT:
        input_state.quit = true
    case sdl2.EventType.KEYDOWN:
        key := event.key
        #partial switch key.keysym.sym {
        case sdl2.Keycode.SPACE:
            input_state.space = .Pressed
        case:
        }
    case sdl2.EventType.KEYUP:
        key := event.key
        #partial switch key.keysym.sym {
        case sdl2.Keycode.SPACE:
            input_state.space = .Released
        case:
        }
    case sdl2.EventType.MOUSEMOTION:
        motion := event.motion
        input_state.mouse_screen_positon = {motion.x, motion.y}
        input_state.mouse_delta = {motion.xrel, motion.yrel}
    case sdl2.EventType.MOUSEBUTTONDOWN:
        button := event.button
        switch button.button {
        case 1:
            input_state.lmb = .Pressed
        case 3:
            input_state.lmb = .Pressed
        case:
        }
    case sdl2.EventType.MOUSEBUTTONUP:
        button := event.button
        switch button.button {
        case 1:
            input_state.lmb = .Released
        case 3:
            input_state.lmb = .Released
        case:
        }
    case:
    }
}
