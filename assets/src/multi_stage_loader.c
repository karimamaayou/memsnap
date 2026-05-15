#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "lab_common.h"

int run_multi_stage(const char *payload_path) {
    printf("[*] Multi-stage loader\n");
    
    printf("[*] Stage 1: Dropper (PID: %d)\n", getpid());
    set_flag("/tmp/.stage1_dropper");
    
    pid_t stage2 = fork();
    if (stage2 == 0) {
        setsid();
        printf("[+] Stage 2: Downloader (PID: %d)\n", getpid());
        set_flag("/tmp/.stage2_downloader");
        sleep(2);
        
        pid_t stage3 = fork();
        if (stage3 == 0) {
            printf("[+] Stage 3: Payload (PID: %d)\n", getpid());
            set_flag("/tmp/.stage3_payload");
            execl(payload_path, payload_path, NULL);
            _exit(1);
        }
        
        FILE *f = fopen("/tmp/stage3.pid", "w");
        if (f) { fprintf(f, "%d", stage3); fclose(f); }
        
        for (;;) pause();
        _exit(0);
    }
    
    printf("[*] Chain: %d (dropper) -> %d (downloader) -> ...\n", getpid(), stage2);
    set_flag("/tmp/.multi_stage_active");
    return 0;
}

int main(int argc, char *argv[]) {
    const char *payload = argc > 1 ? argv[1] : "assets/build/pause_binary";
    return run_multi_stage(payload);
}
