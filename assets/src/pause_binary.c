int main(void) {
    for (;;) { __asm__ volatile("pause"); }
    return 0;
}
