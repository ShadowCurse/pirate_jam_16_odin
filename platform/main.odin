package platform

import "core:fmt"
import "core:slice"
import "core:time"
import "vendor:sdl2"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
    memory := memory_create()
    context.allocator = memory_perm_allocator(&memory)
    context.temp_allocator = memory_scatch_allocator(&memory)
    context.logger = logger_create()

    if sdl2.Init({.VIDEO, .AUDIO}) != 0 {
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
    runtime_init_fn, runtime_run_fn, err := runtime_load(&runtime)
    if err != nil {
        log_err("Could not load runtime: %s", err)
    }

    runtime_entry := runtime_init_fn(&memory, cast(u16)surface.w, cast(u16)surface.h)

    log_info("Running the runtime")
    input_state: InputState = {}
    event: sdl2.Event = ---
    before := time.now()
    for {
        now := time.now()
        dt_ns := cast(u64)time.diff(before, now)
        before = now

        input_state_reset_keys(&input_state)
        for sdl2.PollEvent(&event) {
            input_state_update(&input_state, &event)

            if runtime_reload_event(&event) {
                _, new_runtime_run_fn, err := runtime_load(&runtime)
                if err != nil {
                    log_err("Could not load runtime: %s. Skipping calling runtime.", err)
                    runtime_run_fn = nil
                } else {
                    log_info("Loaded new runtime")
                    runtime_run_fn = new_runtime_run_fn
                }
            }

            if surface_resize_event(&event) do surface = sdl2.GetWindowSurface(window)

        }
        if input_state.quit do break

        surface_data := slice.from_ptr(
            cast([^]u8)surface.pixels,
            cast(int)surface.w * cast(int)surface.h * 4,
        )

        if runtime_run_fn != nil {
            sdl2.FillRect(surface, nil, 0)
            runtime_run_fn(
                dt_ns,
                runtime_entry,
                &memory,
                surface_data,
                cast(u16)surface.w,
                cast(u16)surface.h,
                &input_state,
            )
            sdl2.UpdateWindowSurface(window)
        }
    }
}

surface_resize_event :: proc(event: ^sdl2.Event) -> bool {
    #partial switch event.type {
    case sdl2.EventType.WINDOWEVENT:
        window_event := event.window
        return window_event.event == .RESIZED
    }
    return false
}

RuntimeInitFn :: #type proc(memory: ^Memory, surface_width: u16, surface_height: u16) -> rawptr
RuntimeRunFn :: #type proc(
    dt_ns: u64,
    entry_point: rawptr,
    memory: ^Memory,
    surface_data: []u8,
    surface_width: u16,
    surface_height: u16,
    input_state: ^InputState,
)
RUNTIME_LIB_PATH :: "game.so"
RUNTIME_INIT_EXPORT_NAME :: "runtime_init"
RUNTIME_RUN_EXPORT_NAME :: "runtime_run"

Runtime :: struct {
    handle: rawptr,
}

RuntimeError :: enum byte {
    None         = 0,
    NoRuntimeLib = 1,
    NoRuntimeFn  = 2,
}

import "core:sys/posix"

runtime_load :: proc(runtime: ^Runtime) -> (RuntimeInitFn, RuntimeRunFn, RuntimeError) {
    if runtime.handle != nil {
        log_info("Closing old runtime handle")
        assert(posix.dlclose(auto_cast runtime.handle) == 0, "Could not close old runtime")
    }

    new_handle := posix.dlopen(RUNTIME_LIB_PATH, {.NOW})
    if new_handle == nil {
        log_err("Cannot open new runtime")
        return nil, nil, .NoRuntimeLib
    }

    new_runtime_init := posix.dlsym(new_handle, RUNTIME_INIT_EXPORT_NAME)
    if new_runtime_init == nil {
        log_err("No %s entry in the runtime", RUNTIME_INIT_EXPORT_NAME)
        assert(posix.dlclose(new_handle) == 0, "Could not close new runtime")
        return nil, nil, .NoRuntimeFn
    }

    new_runtime_run := posix.dlsym(new_handle, RUNTIME_RUN_EXPORT_NAME)
    if new_runtime_init == nil {
        log_err("No %s entry in the runtime", RUNTIME_RUN_EXPORT_NAME)
        assert(posix.dlclose(new_handle) == 0, "Could not close new runtime")
        return nil, nil, .NoRuntimeFn
    }

    runtime.handle = new_handle
    return cast(RuntimeInitFn)new_runtime_init, cast(RuntimeRunFn)new_runtime_run, nil
}

runtime_reload_event :: proc(event: ^sdl2.Event) -> bool {
    #partial switch event.type {
    case sdl2.EventType.KEYDOWN:
        key := event.key
        return key.keysym.sym == sdl2.Keycode.F5
    }
    return false
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
