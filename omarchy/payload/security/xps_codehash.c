/* xps-codehash: reads a code from standard input, prints its salted hash. The code never appears on a command line. */
#include "xps_check.h"
#include <stdio.h>
#include <string.h>

int main(void)
{
    char code[128], out[256];
    if (!fgets(code, sizeof code, stdin))
        return 1;
    code[strcspn(code, "\r\n")] = 0;
    if (xps_make_hash(code, out, sizeof out) != 0)
        return 1;
    puts(out);
    return 0;
}
