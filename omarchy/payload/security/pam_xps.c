/* pam_xps: second step of the lock screen.
 * If the enrolled USB stick is plugged in -> success.
 * If not -> ask for the recovery code. Right code -> success, wrong code -> failure.
 * If the feature was never set up (no config file) -> ignored, so it can never lock you out by accident. */
#define _GNU_SOURCE
#define PAM_SM_AUTH
#include "xps_check.h"
#include <security/pam_appl.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
    (void)flags;
    const char *cfg = "/etc/xps-security/xps.conf";
    const char *usbdir = "/dev/disk/by-id";
    for (int i = 0; i < argc; i++) {
        if (!strncmp(argv[i], "config=", 7))
            cfg = argv[i] + 7;
        else if (!strncmp(argv[i], "usbdir=", 7))
            usbdir = argv[i] + 7;
    }

    struct xps_conf c;
    int r = xps_load_config(cfg, &c);
    if (r == 1)
        return PAM_IGNORE;
    if (r < 0) {
        pam_syslog(pamh, LOG_ERR, "xps: security config is unreadable or invalid");
        return PAM_AUTH_ERR;
    }

    if (xps_usb_present(usbdir, c.usb_id))
        return PAM_SUCCESS;

    char *resp = NULL;
    int rc = pam_prompt(pamh, PAM_PROMPT_ECHO_OFF, &resp, "USB key not found. Recovery code: ");
    if (rc != PAM_SUCCESS || !resp)
        return PAM_AUTH_ERR;
    int ok = xps_code_ok(c.code_hash, resp);
    explicit_bzero(resp, strlen(resp));
    free(resp);
    if (!ok) {
        pam_fail_delay(pamh, 3000000);
        return PAM_AUTH_ERR;
    }
    return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
    (void)pamh; (void)flags; (void)argc; (void)argv;
    return PAM_SUCCESS;
}
