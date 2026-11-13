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
#include <signal.h>
#include <syslog.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>

/* Runs the face check program (fixed path, set by root in the PAM file). 1 = face recognised.
 * Gives up after 15 seconds so a broken camera can never hang the lock screen. */
static int face_ok(const char *cmd)
{
    pid_t pid = fork();
    if (pid < 0)
        return 0;
    if (pid == 0) {
        int nul = open("/dev/null", O_RDWR);
        if (nul >= 0) {
            dup2(nul, 0);
            dup2(nul, 1);
            dup2(nul, 2);
        }
        char *args[] = { (char *)cmd, (char *)"verify", NULL };
        execv(cmd, args);
        _exit(127);
    }
    for (int i = 0; i < 150; i++) {
        int st;
        pid_t r = waitpid(pid, &st, WNOHANG);
        if (r == pid)
            return WIFEXITED(st) && WEXITSTATUS(st) == 0;
        if (r < 0)
            return 0;
        struct timespec ts = { 0, 100000000 };
        nanosleep(&ts, NULL);
    }
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
    return 0;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv)
{
    (void)flags;
    const char *cfg = "/etc/xps-security/xps.conf";
    const char *usbdir = "/dev/disk/by-id";
    const char *facecmd = "/usr/local/bin/xps-face";
    for (int i = 0; i < argc; i++) {
        if (!strncmp(argv[i], "config=", 7))
            cfg = argv[i] + 7;
        else if (!strncmp(argv[i], "usbdir=", 7))
            usbdir = argv[i] + 7;
        else if (!strncmp(argv[i], "facecmd=", 8))
            facecmd = argv[i] + 8;
    }

    struct xps_conf c;
    int r = xps_load_config(cfg, &c);
    if (r == 1)
        return PAM_IGNORE;
    if (r < 0) {
        pam_syslog(pamh, LOG_ERR, "xps: security config is unreadable or invalid");
        return PAM_AUTH_ERR;
    }

    const char *why = "USB key not found. Recovery code: ";
    if (xps_usb_present(usbdir, c.usb_id)) {
        if (!c.face || face_ok(facecmd))
            return PAM_SUCCESS;
        why = "Face not recognised. Recovery code: ";
    }

    char *resp = NULL;
    int rc = pam_prompt(pamh, PAM_PROMPT_ECHO_OFF, &resp, "%s", why);
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
