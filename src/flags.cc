//
// flags.cc
// Copyright (C) 2017 4paradigm.com
// Author wangtaize 
// Date 2017-04-07
//

#include <gflags/gflags.h>

DEFINE_int32(gc_interval, 120, "the gc interval of tablet every two hour");
DEFINE_int32(gc_pool_size, 2, "the size of tablet gc thread pool");

