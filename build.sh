odin build platform.odin -file -default-to-nil-allocator -no-dynamic-literals
odin build game -default-to-nil-allocator -no-dynamic-literals -no-entry-point -build-mode:shared

