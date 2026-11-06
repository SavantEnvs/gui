// Linked into the fuzz binary (see build.sh). Plumbing only; no upstream behavior changes.
#include <stdlib.h>

// Leak detection is off by default for the fleet (SPEC §6.2 item 15).
extern "C" int __lsan_is_turned_off() { return 1; }

// Bitcoin Core's `fuzz` binary picks its harness from the FUZZ env var and exits when it is unset.
// Each Mayhemfile sets FUZZ in its cmd env; this default (overwrite=0, so an explicit FUZZ always
// wins) only makes a bare `/mayhem/fuzz` runnable, which the image smoke check relies on.
__attribute__((constructor)) static void select_default_fuzz_target() { setenv("FUZZ", "hex", 0); }
