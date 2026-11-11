/* xps-pamtest <service> <user>: runs a real PAM login check.
 * Answers come from the XPS_TEST_ANSWERS variable (separated by ;) or, if unset, are typed at the keyboard. */
#define _GNU_SOURCE
#include <security/pam_appl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

static char *answers;
static char *save;
static int scripted;

static char *next_answer(const char *prompt, int echo)
{
    if (scripted) {
        char *a = strtok_r(answers ? answers : NULL, ";", &save);
        answers = NULL;
        return strdup(a ? a : "");
    }
    fprintf(stderr, "%s", prompt);
    struct termios old, quiet;
    int have = (tcgetattr(0, &old) == 0);
    if (have && !echo) {
        quiet = old;
        quiet.c_lflag &= ~ECHO;
        tcsetattr(0, TCSANOW, &quiet);
    }
    char buf[256];
    char *got = fgets(buf, sizeof buf, stdin);
    if (have && !echo) {
        tcsetattr(0, TCSANOW, &old);
        fputc('\n', stderr);
    }
    if (!got)
        return strdup("");
    buf[strcspn(buf, "\r\n")] = 0;
    return strdup(buf);
}

static int conv(int n, const struct pam_message **msg, struct pam_response **resp, void *data)
{
    (void)data;
    *resp = calloc(n, sizeof **resp);
    if (!*resp)
        return PAM_CONV_ERR;
    for (int i = 0; i < n; i++) {
        switch (msg[i]->msg_style) {
        case PAM_PROMPT_ECHO_OFF:
            (*resp)[i].resp = next_answer(msg[i]->msg, 0);
            break;
        case PAM_PROMPT_ECHO_ON:
            (*resp)[i].resp = next_answer(msg[i]->msg, 1);
            break;
        default:
            fprintf(stderr, "%s\n", msg[i]->msg);
        }
    }
    return PAM_SUCCESS;
}

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr, "usage: xps-pamtest <service> <user>\n");
        return 2;
    }
    const char *env = getenv("XPS_TEST_ANSWERS");
    if (env) {
        scripted = 1;
        answers = strdup(env);
    }
    struct pam_conv c = { conv, NULL };
    pam_handle_t *h = NULL;
    int rc = pam_start(argv[1], argv[2], &c, &h);
    if (rc == PAM_SUCCESS)
        rc = pam_authenticate(h, 0);
    if (rc == PAM_SUCCESS)
        rc = pam_acct_mgmt(h, 0);
    printf(rc == PAM_SUCCESS ? "AUTH OK\n" : "AUTH FAILED: %s\n", pam_strerror(h, rc));
    pam_end(h, rc);
    return rc == PAM_SUCCESS ? 0 : 1;
}
