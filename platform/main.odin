package platform

import "core:fmt"
import "core:slice"
import "vendor:sdl2"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
    memory := memory_create()
    context.allocator = memory_perm_allocator(&memory)
    context.temp_allocator = memory_scatch_allocator(&memory)
    context.logger = logger_create()

    if sdl2.Init({.VIDEO}) != 0 {
        log_err("Could not init SDL2: %s", sdl2.GetError())
        return
    }
    defer sdl2.Quit()

    window := sdl2.CreateWindow("pirate_jam_odin", 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {})
    if window == nil {
        log_err("Could not create SDL2 window: %s", sdl2.GetError())
        return
    }
    defer sdl2.DestroyWindow(window)
    sdl2.ShowWindow(window)
    surface := sdl2.GetWindowSurface(window)

    runtime: Runtime
    fn, err := runtime_load(&runtime)
    if err != nil {
        log_err("Could not load runtime: %s", err)
    }

    surface_data := slice.from_ptr(cast([^]u8)surface.pixels, WINDOW_WIDTH * WINDOW_HEIGHT * 4)
    log_info("Running the runtime")
    input_state: InputState = {}
    event: sdl2.Event = ---
    runtime_entry: rawptr = nil
    for {
        input_state_reset_keys(&input_state)
        for sdl2.PollEvent(&event) {
            input_state_update(&input_state, &event)
        }
        if input_state.quit do break

        sdl2.FillRect(surface, nil, 0)

        runtime_entry = fn(
            runtime_entry,
            &memory,
            surface_data,
            WINDOW_WIDTH,
            WINDOW_HEIGHT,
            &input_state,
        )
        sdl2.UpdateWindowSurface(window)
    }
}

RuntimeFn :: #type proc(
    entry_point: rawptr,
    memory: ^Memory,
    surface_data: []u8,
    surface_width: u16,
    surface_height: u16,
    input_state: ^InputState,
) -> rawptr
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

input_state_update :: proc(input_state: ^InputState, event: ^sdl2.Event) {
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
