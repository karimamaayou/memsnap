#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "lab_common.h"

void cpu_burn() {
    volatile unsigned long long x = 0;
    for (int i = 0; i < 100000000; i++) {
        x += i * i * i;
    }
}

int run_cryptominer_sim(const char *pool_host, int pool_port) {
    pid_t child;

    printf("[*] Cryptominer Simulation\n");
    if (pool_host)
        printf("[*] Target pool: %s:%d\n", pool_host, pool_port);
    else
        printf("[*] No pool configured - running CPU burn loop\n");

    child = fork();
    if (child == -1) {
        perror("[-] fork failed");
        return -1;
    }

    if (child == 0) {
        printf("[+] Miner started - PID: %d\n", getpid());
        for (int round = 0; ; round++) {
            cpu_burn();
            if (round % 10 == 0) {
                printf("[miner] Share accepted - round %d (simulated)\n", round);
            }
        }
        _exit(0);
    }

    /* Save PID for cleanup */
    FILE *pf = fopen("/tmp/miner_sim.pid", "w");
    if (pf) { fprintf(pf, "%d", child); fclose(pf); }

     set_flag("/tmp/.cryptominer_active");
     return 0;
}

int main(int argc, char *argv[]) {
    const char *pool = NULL;
    int port = 3333;

    if (argc > 1) pool = argv[1];
    if (argc > 2) port = atoi(argv[2]);

    return run_cryptominer_sim(pool, port);
}
