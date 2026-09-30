#ifndef ZU_CONFIG_H
#define ZU_CONFIG_H

/* Constants shared by the R glue and the TinyCBOR-facing code. No R headers
 * here: zu_tinycbor_check.c includes this beside TinyCBOR's internals. */

/* The hard ceiling on max_depth (design section 11). TinyCBOR's validator and
 * our build phase both recurse. The validator starts with
 * CBOR_PARSER_MAX_RECURSIONS and charges each container or tag one level
 * before testing for zero, so the deepest item it accepts is one less:
 * 1023 levels, measured at Stage 1. zu_tinycbor_check.c fails the build if
 * the two drift apart. */
#define ZU_MAX_DEPTH_CAP 1023

#endif
