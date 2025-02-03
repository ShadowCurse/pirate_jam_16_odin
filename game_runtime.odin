package game_runtime

import "game"

@(export)
runtime_main :: proc(memory: ^game.Memory) {
    game.log_info("runtime_main")
}
