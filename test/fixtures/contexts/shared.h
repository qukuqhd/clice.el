#pragma once

#ifdef FAST
FAST_TYPE get_fast();
#else
SLOW_TYPE get_slow();
#endif

int common();
