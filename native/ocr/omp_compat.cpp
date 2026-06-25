// Stub for __kmpc_dispatch_deinit which is missing from NDK 28 (LLVM 19)
// libomp.  The opencv-mobile prebuilts were compiled with a newer LLVM that
// references this symbol.  It is a dispatch-loop cleanup function; a no-op
// stub is safe because the dispatch state is overwritten on next use.
//
// When a future NDK ships libomp with this symbol, this file can be removed.

#include <stdint.h>

extern "C" void __kmpc_dispatch_deinit(void* loc, int32_t gtid) {
    (void)loc;
    (void)gtid;
}
