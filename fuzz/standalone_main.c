/* Drives a libFuzzer target over files, for platforms whose compiler has no
 * libFuzzer runtime (Apple's): builds with ASan and UBSan alone and runs each
 * named file once. Used by tools/run-fuzz's --replay mode. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        if (!f) {
            perror(argv[i]);
            return 2;
        }
        uint8_t *buf = NULL;
        size_t n = 0, cap = 0;
        int c;
        while ((c = fgetc(f)) != EOF) {
            if (n == cap) {
                cap = cap ? cap * 2 : 4096;
                buf = realloc(buf, cap);
                if (!buf)
                    return 2;
            }
            buf[n++] = (uint8_t) c;
        }
        fclose(f);
        LLVMFuzzerTestOneInput(buf, n);
        free(buf);
    }
    printf("replayed %d inputs\n", argc - 1);
    return 0;
}
