#ifndef STUB_PAM_APPL_H
#define STUB_PAM_APPL_H
typedef struct pam_handle pam_handle_t;
struct pam_message { int msg_style; const char *msg; };
struct pam_response { char *resp; int resp_retcode; };
struct pam_conv { int (*conv)(int, const struct pam_message **, struct pam_response **, void *); void *appdata_ptr; };
#define PAM_SUCCESS 0
#define PAM_CONV_ERR 19
#define PAM_AUTH_ERR 7
#define PAM_IGNORE 25
#define PAM_PROMPT_ECHO_OFF 1
#define PAM_PROMPT_ECHO_ON 2
#define PAM_ERROR_MSG 3
#define PAM_TEXT_INFO 4
int pam_start(const char *, const char *, const struct pam_conv *, pam_handle_t **);
int pam_end(pam_handle_t *, int);
int pam_authenticate(pam_handle_t *, int);
int pam_acct_mgmt(pam_handle_t *, int);
const char *pam_strerror(pam_handle_t *, int);
#endif
