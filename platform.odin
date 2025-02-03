package platform

import "core:fmt"
import "game"

@(export = false)
main :: proc() {
    memory := game.memory_create()
    context.allocator = game.memory_perm_allocator(&memory)
    context.temp_allocator = game.memory_scatch_allocator(&memory)
    context.logger = game.logger_create()

    runtime: Runtime
    fn, err := runtime_load(&runtime)
    if err != nil {
        game.log_err("Could not load runtime: %", err)
    }
    game.log_info("Running the runtime")
    fn(&memory)
}

RuntimeFn :: #type proc(memory: ^game.Memory)
RUNTIME_LIB_PATH :: "game_runtime.so"
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
