package platform

import "base:runtime"
import "core:mem"
import "core:simd"
import "core:slice"
import "vendor:sdl2"

AUDIO_FREQ :: 44100
AUDIO_CHANNELS :: 2
AUDIO_SAMPLES :: 4096
Audio :: struct {
    device_id:           sdl2.AudioDeviceID,
    global_volume:       f32,
    playing_soundtracks: [32]PlayingSoundtrack,
    _callback_buffer:    []simd.i16x16,
}

PlayingSoundtrack :: struct {
    soundtrack:                    Soundtrack,
    progress_bytes:                u32,
    left_current_volume:           f32,
    left_target_volume:            f32,
    left_volume_delta_per_sample:  f32,
    right_current_volume:          f32,
    right_target_volume:           f32,
    right_volume_delta_per_sample: f32,
    is_playing:                    bool,
}

Soundtrack :: distinct []u8

audio_callback :: proc "c" (userdata: rawptr, stream: [^]u8, stream_length: i32) {
    audio := cast(^Audio)userdata
    stream_i16x16 := slice.from_ptr(cast([^]simd.i16x16)stream, cast(int)stream_length / 32)

    mem.set(raw_data(audio._callback_buffer), 0, len(audio._callback_buffer) * 32)
    for &ps, i in audio.playing_soundtracks {
        if !ps.is_playing do continue

        remaining_bytes := cast(u32)len(ps.soundtrack) - ps.progress_bytes
        copy_bytes := min(remaining_bytes, cast(u32)stream_length)

        tail_bytes := copy_bytes % 32
        // TODO do smth with tail bytes
        if tail_bytes != 0 do copy_bytes -= tail_bytes

        src_bytes := cast([]u8)(ps.soundtrack)[ps.progress_bytes:][:copy_bytes]

        copy_simd := copy_bytes / 32
        src_i16x16 := slice.from_ptr(cast([^]simd.i16x16)raw_data(src_bytes), cast(int)copy_simd)

        for i in 0 ..< copy_simd {
            audio._callback_buffer[i] = simd.saturating_add(
                audio._callback_buffer[i],
                src_i16x16[i],
            )
        }
        ps.progress_bytes += copy_bytes
        if cast(u32)len(ps.soundtrack) <= ps.progress_bytes do ps.is_playing = false
    }

    copy(stream_i16x16, audio._callback_buffer)
}

audio_init :: proc(audio: ^Audio, global_volume: f32) {
    wanted_spec := sdl2.AudioSpec {
        freq     = AUDIO_FREQ,
        format   = sdl2.AUDIO_S16,
        channels = AUDIO_CHANNELS,
        samples  = AUDIO_SAMPLES,
        callback = audio_callback,
        userdata = audio,
    }
    audio.device_id = sdl2.OpenAudioDevice(nil, false, &wanted_spec, nil, false)
    audio.global_volume = global_volume

    callback_buffer, err := make([]simd.i16x16, 512)
    assert(err == nil, "Cannot allocate memory for the audio callback")
    audio._callback_buffer = callback_buffer
}

audio_pause :: proc(audio: ^Audio) {
    sdl2.PauseAudioDevice(audio.device_id, true)
}

audio_unpause :: proc(audio: ^Audio) {
    sdl2.PauseAudioDevice(audio.device_id, false)
}

audio_play :: proc(audio: ^Audio, soundtrack: Soundtrack, left_volume, right_volume: f32) {
    for &ps, i in audio.playing_soundtracks {
        if !ps.is_playing {
            ps = {
                soundtrack           = soundtrack,
                left_current_volume  = left_volume,
                right_current_volume = right_volume,
                is_playing           = true,
            }
            return
        }
    }
    log_warn("Trying to play soundtrack, but all slots are occupied. Skipping.")
}

audio_is_playing :: proc(audio: ^Audio, soundtrack: Soundtrack) -> bool {
    is_playing := false
    for &ps, i in audio.playing_soundtracks {
        if raw_data(ps.soundtrack) == raw_data(soundtrack) {
            is_playing |= ps.is_playing
        }
    }
    return is_playing
}

audio_set_volume :: proc(
    audio: ^Audio,
    soundtrack: Soundtrack,
    left_target_volume, left_time_seconds, right_target_volume, right_time_seconds: f32,
) {
    for &ps, i in audio.playing_soundtracks {
        if raw_data(ps.soundtrack) == raw_data(soundtrack) {
            ps.left_target_volume = left_target_volume
            ps.left_volume_delta_per_sample =
                (left_target_volume - ps.left_current_volume) / (left_time_seconds * AUDIO_FREQ)
            ps.right_target_volume = right_target_volume
            ps.right_volume_delta_per_sample =
                (right_target_volume - ps.right_current_volume) / (right_time_seconds * AUDIO_FREQ)
        }
    }
}

soundtrack_load :: proc(path: cstring) -> Soundtrack {
    spec: sdl2.AudioSpec = ---
    buffer: [^]u8 = ---
    buffer_len: u32 = ---
    loaded_spec := sdl2.LoadWAV(path, &spec, &buffer, &buffer_len)
    assert(loaded_spec != nil, "Cannot load soundrack from path: %s", path)

    soundtrack, err := runtime.make_aligned([]u8, buffer_len, 64)
    assert(err == nil, "Cannot allocate memory for the soundtrack from path: %s", path)

    buffer_slice := slice.from_ptr(buffer, cast(int)buffer_len)
    copy(soundtrack, buffer_slice)

    log_info(
        "Loaded soundtrack from path: %s with specs: freq: %d, format: %d, channels: %d",
        path,
        loaded_spec.freq,
        loaded_spec.format,
        loaded_spec.channels,
    )

    return cast(Soundtrack)soundtrack
}
