package platform

import "base:runtime"
import "core:fmt"
import "core:os"

Logger :: runtime.Logger
Level :: runtime.Logger_Level
Options :: runtime.Logger_Options

DEFAULT_COLOR :: "\x1b[0m"
WHITE :: "\x1b[37m"
HIGH_WHITE :: "\x1b[90m"
YELLOW :: "\x1b[33m"
RED :: "\x1b[31m"

log_debug :: proc(format: string, args: ..any, location := #caller_location) {
    log(.Debug, format, ..args, location = location)
}
log_info :: proc(format: string, args: ..any, location := #caller_location) {
    log(.Info, format, ..args, location = location)
}
log_warn :: proc(format: string, args: ..any, location := #caller_location) {
    log(.Warning, format, ..args, location = location)
}
log_err :: proc(format: string, args: ..any, location := #caller_location) {
    log(.Error, format, ..args, location = location)
}

panic :: proc(format: string, args: ..any, location := #caller_location) -> ! {
    log(.Fatal, format, ..args, location = location)
    runtime.panic("log.panic", location)
}

@(disabled = ODIN_DISABLE_ASSERT)
assert :: proc(condition: bool, format: string, args: ..any, loc := #caller_location) {
    if !condition {
        @(cold)
        internal :: proc(location: runtime.Source_Code_Location, format: string, args: ..any) {
            log(.Fatal, format, ..args, location = location)
            runtime.trap()
        }
        internal(loc, format, ..args)
    }
}


log :: proc(level: Level, format: string, args: ..any, location := #caller_location) {
    logger := context.logger
    if logger.procedure == nil {
        return
    }
    if level < logger.lowest_level {
        return
    }
    // This does the allocation from a temporary allocator
    str := fmt.tprintf(format, ..args)
    logger.procedure(logger.data, level, str, logger.options, location)
}

log_proc :: proc(
    logger_data: rawptr,
    level: Level,
    text: string,
    options: Options,
    location := #caller_location,
) {
    level_text := "INFO"
    color := WHITE
    switch level {
    case .Debug:
        color = HIGH_WHITE
        level_text = "DEBUG"
    case .Info:
        color = WHITE
        level_text = "INFO"
    case .Warning:
        color = YELLOW
        level_text = "WARN"
    case .Error:
        color = RED
        level_text = "ERROR"
    case .Fatal:
        color = RED
        level_text = "FATAL"
    }

    file_name_start := 0
    for c, i in location.file_path {
        if c == '/' {
            file_name_start = i + 1
        }
    }
    file_name := location.file_path[file_name_start:]

    s := os.stream_from_handle(os.stdout)
    fmt.wprintf(
        s,
        "%s[%s:%s:%d:%d:%s]: %s%s\n",
        color,
        file_name,
        location.procedure,
        location.line,
        location.column,
        level_text,
        text,
        DEFAULT_COLOR,
    )
}

logger_create :: proc() -> Logger {
    return Logger{log_proc, nil, .Debug, {}}
}
