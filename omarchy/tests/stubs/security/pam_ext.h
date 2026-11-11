#ifndef STUB_PAM_EXT_H
#define STUB_PAM_EXT_H
#include <security/pam_appl.h>
int pam_prompt(pam_handle_t *, int, char **, const char *, ...);
void pam_syslog(const pam_handle_t *, int, const char *, ...);
int pam_fail_delay(pam_handle_t *, unsigned int);
#endif
