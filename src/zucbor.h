#ifndef ZUCBOR_H
#define ZUCBOR_H

#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

#include "zu_config.h"

/* .Call entry points, registered in init.c. */
SEXP zucbor_build_info(void);

#endif
