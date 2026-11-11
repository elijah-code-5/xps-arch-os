#include "xps_check.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int fails;
#define CHECK(c) do { if (c) printf("PASS: %s\n", #c); else { printf("FAIL: %s\n", #c); fails = 1; } } while (0)

int main(int argc, char **argv)
{
    const char *dir = argc > 1 ? argv[1] : "/tmp";
    struct xps_conf c;
    char path[512], link[512];

    /* config */
    snprintf(path, sizeof path, "%s/none.conf", dir);
    CHECK(xps_load_config(path, &c) == 1);                       /* missing = not set up */
    snprintf(path, sizeof path, "%s/bad.conf", dir);
    FILE *f = fopen(path, "w"); fputs("usb_id=only-this\n", f); fclose(f);
    CHECK(xps_load_config(path, &c) == -1);                      /* half a config is invalid */

    /* hashing */
    char h1[256], h2[256];
    CHECK(xps_make_hash("2468", h1, sizeof h1) == 0);
    CHECK(xps_make_hash("2468", h2, sizeof h2) == 0);
    CHECK(strcmp(h1, h2) != 0);                                  /* random salt */
    CHECK(strstr(h1, "2468") == NULL);                           /* code is not stored */
    CHECK(xps_code_ok(h1, "2468") == 1);
    CHECK(xps_code_ok(h1, "2469") == 0);
    CHECK(xps_code_ok(h1, "") == 0);
    CHECK(xps_code_ok(h1, "24680") == 0);
    CHECK(xps_code_ok("garbage", "2468") == 0);
    CHECK(xps_code_ok(NULL, "2468") == 0);

    /* good config */
    snprintf(path, sizeof path, "%s/good.conf", dir);
    f = fopen(path, "w");
    fprintf(f, "# comment\nusb_id=usb-Test_Stick_123-0:0\ncode_hash=%s\n", h1);
    fclose(f);
    CHECK(xps_load_config(path, &c) == 0);
    CHECK(strcmp(c.usb_id, "usb-Test_Stick_123-0:0") == 0);
    CHECK(xps_code_ok(c.code_hash, "2468") == 1);

    /* usb presence */
    snprintf(link, sizeof link, "%s/usb-Test_Stick_123-0:0", dir);
    unlink(link);
    CHECK(xps_usb_present(dir, c.usb_id) == 0);                  /* not plugged in */
    CHECK(symlink("/dev/null", link) == 0);
    CHECK(xps_usb_present(dir, c.usb_id) == 1);                  /* plugged in */
    CHECK(xps_usb_present(dir, "usb-Other_Stick-0:0") == 0);     /* a different stick does not count */
    CHECK(xps_usb_present(dir, "../etc/passwd") == 0);           /* path tricks refused */
    CHECK(xps_usb_present(dir, "a/b") == 0);
    CHECK(xps_usb_present(dir, "") == 0);
    unlink(link);
    return fails;
}
