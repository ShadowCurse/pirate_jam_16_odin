package platform

import "core:slice"
import posix "core:sys/posix"

FileMemory :: distinct []u8

file_memory_open :: proc(path: cstring) -> FileMemory {
    fd := posix.open(path, {})
    assert(fd != -1, "Cannot open file: %s", path)

    stat: posix.stat_t = ---
    r := posix.fstat(fd, &stat)
    assert(r != .FAIL, "Cannot get file info: %s", path)
    size := cast(uint)stat.st_size

    ptr := posix.mmap(nil, size, {.READ}, {.PRIVATE}, fd, 0)
    return cast(FileMemory)slice.from_ptr(cast(^u8)ptr, cast(int)size)
}

file_memory_close :: proc(file_memory: ^FileMemory) {
    posix.munmap(raw_data(file_memory^), len(file_memory))
}
