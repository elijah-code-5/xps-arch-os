#define _GNU_SOURCE
#include "xps_check.h"
#include <crypt.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void trim(char *s)
{
    size_t n = strlen(s);
    while (n && (s[n - 1] == '\n' || s[n - 1] == '\r' || s[n - 1] == ' ' || s[n - 1] == '\t'))
        s[--n] = 0;
}

int xps_load_config(const char *path, struct xps_conf *c)
{
    memset(c, 0, sizeof *c);
    FILE *f = fopen(path, "r");
    if (!f)
        return errno == ENOENT ? 1 : -1;
    char line[512];
    int have_usb = 0, have_hash = 0;
    while (fgets(line, sizeof line, f)) {
        trim(line);
        if (!line[0] || line[0] == '#')
            continue;
        char *eq = strchr(line, '=');
        if (!eq)
            continue;
        *eq = 0;
        const char *k = line, *v = eq + 1;
        if (!strcmp(k, "usb_id") && strlen(v) > 0 && strlen(v) < sizeof c->usb_id) {
            strcpy(c->usb_id, v);
            have_usb = 1;
        } else if (!strcmp(k, "face")) {
            c->face = !strcmp(v, "1");
        } else if (!strcmp(k, "code_hash") && strlen(v) > 0 && strlen(v) < sizeof c->code_hash) {
            strcpy(c->code_hash, v);
            have_hash = 1;
        }
    }
    fclose(f);
    return (have_usb && have_hash) ? 0 : -1;
}

int xps_usb_present(const char *dir, const char *id)
{
    if (!dir || !id || !*id || strchr(id, '/') || strstr(id, ".."))
        return 0;
    char path[1024];
    if (snprintf(path, sizeof path, "%s/%s", dir, id) >= (int)sizeof path)
        return 0;
    return access(path, F_OK) == 0;
}

int xps_code_ok(const char *hash, const char *code)
{
    if (!hash || !code || hash[0] != '$')
        return 0;
    struct crypt_data *d = calloc(1, sizeof *d);
    if (!d)
        return 0;
    char *r = crypt_r(code, hash, d);
    int ok = 0;
    if (r && r[0] != '*') {
        size_t a = strlen(r), b = strlen(hash);
        if (a == b) {
            unsigned char diff = 0;
            for (size_t i = 0; i < a; i++)
                diff |= (unsigned char)(r[i] ^ hash[i]);
            ok = (diff == 0);
        }
    }
    explicit_bzero(d, sizeof *d);
    free(d);
    return ok;
}

int xps_make_hash(const char *code, char *out, size_t n)
{
    static const char alpha[] = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    unsigned char rnd[16];
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0)
        return -1;
    if (read(fd, rnd, sizeof rnd) != (ssize_t)sizeof rnd) {
        close(fd);
        return -1;
    }
    close(fd);
    char setting[64] = "$6$rounds=100000$";
    size_t l = strlen(setting);
    for (int i = 0; i < 16; i++)
        setting[l + i] = alpha[rnd[i] % 64];
    setting[l + 16] = '$';
    setting[l + 17] = 0;
    struct crypt_data *d = calloc(1, sizeof *d);
    if (!d)
        return -1;
    char *r = crypt_r(code, setting, d);
    int rc = -1;
    if (r && r[0] == '$' && strlen(r) < n) {
        strcpy(out, r);
        rc = 0;
    }
    explicit_bzero(d, sizeof *d);
    free(d);
    return rc;
}
