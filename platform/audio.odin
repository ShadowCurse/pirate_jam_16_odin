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
    soundtrack:     Soundtrack,
    progress_bytes: u32,
    left:           Volume,
    right:          Volume,
    is_playing:     bool,
}

Volume :: struct {
    current:          f32,
    target:           f32,
    delta_per_sample: f32,
}

Soundtrack :: distinct []u8

audio_callback :: proc "c" (userdata: rawptr, stream: [^]u8, stream_length: i32) {
    audio := cast(^Audio)userdata
    stream_i16x16 := slice.from_ptr(cast([^]simd.i16x16)stream, cast(int)stream_length / 32)
    mem.set(raw_data(audio._callback_buffer), 0, len(audio._callback_buffer) * 32)
    for &ps in audio.playing_soundtracks {
        if !ps.is_playing do continue

        remaining_bytes := cast(u32)len(ps.soundtrack) - ps.progress_bytes
        copy_bytes := min(remaining_bytes, cast(u32)stream_length)
        src := cast([]u8)(ps.soundtrack)[ps.progress_bytes:][:copy_bytes]

        copy_simd := copy_bytes / 32
        src_i16x16 := slice.from_ptr(cast([^]simd.i16x16)raw_data(src), cast(int)copy_simd)

        i_when_left_target_will_be_reached, sample_index_when_left_target_will_be_reached :=
            audio_callback_calculate_volume(&ps.left, copy_simd)
        i_when_right_target_will_be_reached, sample_index_when_right_target_will_be_reached :=
            audio_callback_calculate_volume(&ps.right, copy_simd)

        for i in 0 ..< copy_simd {
            samples := simd.to_array(src_i16x16[i])

            left_channel_simd := simd.f32x8 {
                cast(f32)samples[0],
                cast(f32)samples[2],
                cast(f32)samples[4],
                cast(f32)samples[6],
                cast(f32)samples[8],
                cast(f32)samples[10],
                cast(f32)samples[12],
                cast(f32)samples[14],
            }
            left_channel := audio_callback_process_channel(
                &ps.left,
                audio.global_volume,
                i,
                i_when_left_target_will_be_reached,
                sample_index_when_left_target_will_be_reached,
                left_channel_simd,
            )

            right_channel_simd := simd.f32x8 {
                cast(f32)samples[1],
                cast(f32)samples[3],
                cast(f32)samples[5],
                cast(f32)samples[7],
                cast(f32)samples[9],
                cast(f32)samples[11],
                cast(f32)samples[13],
                cast(f32)samples[15],
            }
            right_channel := audio_callback_process_channel(
                &ps.right,
                audio.global_volume,
                i,
                i_when_right_target_will_be_reached,
                sample_index_when_right_target_will_be_reached,
                right_channel_simd,
            )

            src_with_volume := simd.i16x16 {
                cast(i16)left_channel[0],
                cast(i16)right_channel[0],
                cast(i16)left_channel[1],
                cast(i16)right_channel[1],
                cast(i16)left_channel[2],
                cast(i16)right_channel[2],
                cast(i16)left_channel[3],
                cast(i16)right_channel[3],
                cast(i16)left_channel[4],
                cast(i16)right_channel[4],
                cast(i16)left_channel[5],
                cast(i16)right_channel[5],
                cast(i16)left_channel[6],
                cast(i16)right_channel[6],
                cast(i16)left_channel[7],
                cast(i16)right_channel[7],
            }

            audio._callback_buffer[i] = simd.saturating_add(
                audio._callback_buffer[i],
                src_with_volume,
            )
        }
        ps.progress_bytes += copy_bytes
        if cast(u32)len(ps.soundtrack) <= ps.progress_bytes do ps.is_playing = false
    }

    copy(stream_i16x16, audio._callback_buffer)
}

audio_callback_calculate_volume :: proc "contextless" (
    volume: ^Volume,
    copy_simd: u32,
) -> (
    u32,
    u32,
) {
    if volume.delta_per_sample == 0 do return 0, 0

    samples_to_reach_target := cast(u32)(abs(volume.target - volume.current) /
        volume.delta_per_sample)
    // we process 8 samples at a time
    i_when_target_will_be_reached := samples_to_reach_target / 8
    sample_index_when_target_will_be_reached :=
        samples_to_reach_target - i_when_target_will_be_reached * 8

    if i_when_target_will_be_reached < copy_simd {
        volume.current = volume.target
        volume.delta_per_sample = 0
    } else {
        volume.current += volume.delta_per_sample * cast(f32)copy_simd * 8
    }

    return i_when_target_will_be_reached, sample_index_when_target_will_be_reached
}

audio_callback_process_channel :: proc "contextless" (
    volume: ^Volume,
    global_volume: f32,
    i: u32,
    target_i: u32,
    sample_index: u32,
    channel: simd.f32x8,
) -> [8]f32 {
    current_volume_simd :=
        cast(simd.f32x8)volume.current + cast(f32)i * volume.delta_per_sample * 8

    if i < target_i {
        d := volume.delta_per_sample
        current_volume_simd += cast(simd.f32x8){d, d, d, d, d, d, d, d}
        current_volume_simd += cast(simd.f32x8){0, d, d, d, d, d, d, d}
        current_volume_simd += cast(simd.f32x8){0, 0, d, d, d, d, d, d}
        current_volume_simd += cast(simd.f32x8){0, 0, 0, d, d, d, d, d}
        current_volume_simd += cast(simd.f32x8){0, 0, 0, 0, d, d, d, d}
        current_volume_simd += cast(simd.f32x8){0, 0, 0, 0, 0, d, d, d}
        current_volume_simd += cast(simd.f32x8){0, 0, 0, 0, 0, 0, d, d}
        current_volume_simd += cast(simd.f32x8){0, 0, 0, 0, 0, 0, 0, d}
    } else if i == target_i {
        d := volume.delta_per_sample
        q := cast(f32)sample_index
        v := [8]f32 {
            d * min(q + 1, 1),
            d * min(q + 1, 2),
            d * min(q + 1, 3),
            d * min(q + 1, 4),
            d * min(q + 1, 5),
            d * min(q + 1, 6),
            d * min(q + 1, 7),
            d * min(q + 1, 8),
        }
        current_volume_simd += simd.from_array(v)
    }
    return simd.to_array(channel * global_volume * current_volume_simd)
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
    for &ps in audio.playing_soundtracks {
        if !ps.is_playing {
            ps = {
                soundtrack = soundtrack,
                left = {current = left_volume},
                right = {current = right_volume},
                is_playing = true,
            }
            return
        }
    }
    log_warn("Trying to play soundtrack, but all slots are occupied. Skipping.")
}

audio_is_playing :: proc(audio: ^Audio, soundtrack: Soundtrack) -> bool {
    is_playing := false
    for &ps in audio.playing_soundtracks {
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
    for &ps in audio.playing_soundtracks {
        if raw_data(ps.soundtrack) == raw_data(soundtrack) {
            ps.left.target = left_target_volume
            ps.left.delta_per_sample =
                (left_target_volume - ps.left.current) / (left_time_seconds * AUDIO_FREQ)
            ps.right.target = right_target_volume
            ps.right.delta_per_sample =
                (right_target_volume - ps.right.current) / (right_time_seconds * AUDIO_FREQ)
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
