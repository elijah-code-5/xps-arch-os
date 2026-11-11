#ifndef XPS_CHECK_H
#define XPS_CHECK_H
#include <stddef.h>

struct xps_conf {
    char usb_id[256];     /* name of the stick in /dev/disk/by-id, e.g. usb-SanDisk_Ultra_4C53...-0:0 */
    char code_hash[256];  /* salted hash of the recovery code (never the code itself) */
};

/* 0 = loaded, 1 = no config file (feature not set up), -1 = unreadable or invalid */
int xps_load_config(const char *path, struct xps_conf *c);
/* 1 if the stick is plugged in, else 0 */
int xps_usb_present(const char *dir, const char *usb_id);
/* 1 if the code matches the stored hash, else 0 */
int xps_code_ok(const char *hash, const char *code);
/* 0 on success: writes a new salted hash of the code into out */
int xps_make_hash(const char *code, char *out, size_t n);
#endif
