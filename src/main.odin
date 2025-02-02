package game

main :: proc() {
    memory := memory_create()
    context.allocator = memory_perm_allocator(&memory)
    context.temp_allocator = memory_scatch_allocator(&memory)

    context.logger = logger_create()
    log_info("%d", memory.perm_alloc.last_addr)
    log_warn("%d", memory.scratch_alloc.last_addr)
    log_err("Some error %s %d", "test", 69)
}
