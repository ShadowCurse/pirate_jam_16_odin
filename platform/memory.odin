package platform

import "base:runtime"
import "core:log"
import "core:slice"
import "core:sys/posix"

mmap_memory :: proc(size: u32) -> []u8 {
    ptr := posix.mmap(nil, cast(uint)size, {.READ, .WRITE}, {.PRIVATE, .ANONYMOUS})
    log.assert(ptr != nil, "Cannot mmap memory")
    return slice.from_ptr(cast(^u8)ptr, cast(int)size)
}

BumpAlloc :: struct {
    memory:    []u8,
    last_addr: u32,
}

bump_alloc_alloc :: proc(
    self: ^BumpAlloc,
    size: u32,
    alignment: u32,
) -> (
    []u8,
    runtime.Allocator_Error,
) {
    if cast(u32)len(self.memory) < size {
        return nil, .Out_Of_Memory
    }
    start := (self.last_addr + alignment - 1) & ~(alignment - 1)
    end := start + size
    if cast(u32)len(self.memory) < start || cast(u32)len(self.memory) < end {
        return nil, .Out_Of_Memory
    }
    self.last_addr = end
    return self.memory[start:end], nil
}

bump_alloc_alloc_cycle :: proc(
    self: ^BumpAlloc,
    size: u32,
    alignment: u32,
) -> (
    []u8,
    runtime.Allocator_Error,
) {
    if cast(u32)len(self.memory) < size {
        return nil, .Out_Of_Memory
    }
    start := (self.last_addr + alignment - 1) & ~(alignment - 1)
    end := start + size
    if cast(u32)len(self.memory) < start || cast(u32)len(self.memory) < end {
        start = 0
        end = start + size
    }
    self.last_addr = end
    return self.memory[start:end], nil
}

perm_alloc_proc :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    loc := #caller_location,
) -> (
    mem: []byte,
    err: runtime.Allocator_Error,
) {
    bump_alloc := cast(^BumpAlloc)allocator_data
    size := cast(u32)size
    alignment := cast(u32)alignment
    old_size := cast(u32)old_size

    switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        return bump_alloc_alloc(bump_alloc, size, alignment)
    case .Free:
        return nil, .Mode_Not_Implemented
    case .Free_All:
        bump_alloc.last_addr = 0
        return nil, nil
    case .Resize, .Resize_Non_Zeroed:
        old_data := ([^]byte)(old_memory)

        switch {
        case old_data == nil:
            return bump_alloc_alloc(bump_alloc, size, alignment)
        case size == old_size:
            return old_data[:size], nil
        case size == 0:
            return nil, nil
        case uintptr(old_data) & uintptr(alignment - 1) == 0:
            if size < old_size {
                return old_data[:size], nil
            }
        }

        new_memory := bump_alloc_alloc(bump_alloc, size, alignment) or_return
        copy(new_memory, old_data[:old_size])
        return new_memory, nil
    case .Query_Features:
        return nil, .Mode_Not_Implemented
    case .Query_Info:
        return nil, .Mode_Not_Implemented
    }
    log.panic("Perm allocator ciritical error")
}

scratch_alloc_proc :: proc(
    allocator_data: rawptr,
    mode: runtime.Allocator_Mode,
    size: int,
    alignment: int,
    old_memory: rawptr,
    old_size: int,
    loc := #caller_location,
) -> (
    mem: []byte,
    err: runtime.Allocator_Error,
) {
    bump_alloc := cast(^BumpAlloc)allocator_data
    size := cast(u32)size
    alignment := cast(u32)alignment
    old_size := cast(u32)old_size

    switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
        return bump_alloc_alloc_cycle(bump_alloc, size, alignment)
    case .Free:
        return nil, .Mode_Not_Implemented
    case .Free_All:
        bump_alloc.last_addr = 0
        return nil, nil
    case .Resize, .Resize_Non_Zeroed:
        old_data := ([^]byte)(old_memory)

        switch {
        case old_data == nil:
            return bump_alloc_alloc_cycle(bump_alloc, size, alignment)
        case size == old_size:
            return old_data[:size], nil
        case size == 0:
            return nil, nil
        case uintptr(old_data) & uintptr(alignment - 1) == 0:
            if size < old_size {
                return old_data[:size], nil
            }
        }

        new_memory := bump_alloc_alloc_cycle(bump_alloc, size, alignment) or_return
        copy(new_memory, old_data[:old_size])
        return new_memory, nil
    case .Query_Features:
        return nil, .Mode_Not_Implemented
    case .Query_Info:
        return nil, .Mode_Not_Implemented
    }
    log.panic("Perm allocator ciritical error")
}

Memory :: struct {
    perm_alloc:    BumpAlloc,
    scratch_alloc: BumpAlloc,
}

PERM_MEMORY_SIZE :: 1024 * 1024 * 128
SCRATCH_MEMORY_SIZE :: 4096 * 10
memory_create :: proc() -> Memory {
    perm_memory := mmap_memory(PERM_MEMORY_SIZE)
    scratch_memory := mmap_memory(SCRATCH_MEMORY_SIZE)
    return {perm_alloc = {perm_memory, 0}, scratch_alloc = {scratch_memory, 0}}
}

memory_perm_allocator :: proc(memory: ^Memory) -> runtime.Allocator {
    return runtime.Allocator{procedure = perm_alloc_proc, data = &memory.perm_alloc}
}

memory_scatch_allocator :: proc(memory: ^Memory) -> runtime.Allocator {
    return runtime.Allocator{procedure = scratch_alloc_proc, data = &memory.scratch_alloc}
}
