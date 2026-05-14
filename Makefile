BINDIR = assets/build
CC     = gcc
CFLAGS = -Wall -Wextra -O2

.PHONY: all clean

all: $(BINDIR)/ptrace_inject $(BINDIR)/process_hollow $(BINDIR)/deleted_exe \
     $(BINDIR)/fileless_exec $(BINDIR)/miner_sim $(BINDIR)/evil.so

$(BINDIR):
	mkdir -p $(BINDIR)

$(BINDIR)/ptrace_inject: assets/src/ptrace_inject.c assets/src/lab_common.c | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $^

$(BINDIR)/process_hollow: assets/src/process_hollow.c assets/src/lab_common.c | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $^

$(BINDIR)/deleted_exe: assets/src/deleted_exe.c assets/src/lab_common.c | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $^

$(BINDIR)/fileless_exec: assets/src/fileless_exe.c assets/src/lab_common.c | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $^

$(BINDIR)/miner_sim: assets/src/miner_sim.c assets/src/lab_common.c | $(BINDIR)
	$(CC) $(CFLAGS) -o $@ $^

$(BINDIR)/evil.so: assets/src/evil.c | $(BINDIR)
	$(CC) -shared -fPIC -o $@ $^

clean:
	rm -rf $(BINDIR)