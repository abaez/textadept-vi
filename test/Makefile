STRACE :=
TMUX_EXTRA :=

ifeq ($(DEBUG),1)
STRACE := strace -s4096 -o output/ta.strace
TMUX_EXTRA :=  \; attach
endif
TA := $(STRACE) ../../textadept-curses
TMUX := tmux -f userhome/tmux.conf

# tmux configuration
TMUX_SOCKET := ./output/tmux-socket
TMUX_WIDTH := 80
TMUX_HEIGHT := 24
TMUX_SIZE := -x $(TMUX_WIDTH) -y $(TMUX_HEIGHT)

all: test

output:
	mkdir -p $@
  
clean:
	rm -r output

test: output
	@# Remove previous output file to avoid confusion.
	@rm -f output/results.txt output/sem.fifo
	@touch output/results.txt
	@mkfifo output/sem.fifo
	$(TMUX) -S $(TMUX_SOCKET) -C new-session -d $(TMUX_SIZE) "TESTS=\"$(TESTS)\" bash " \; send-keys "$(TA) --nosession --userhome ./userhome " \; send-keys enter $(TMUX_EXTRA)
	@echo Waiting for test...
	@head -1 output/sem.fifo >/dev/null & tail --pid=$$! --follow=name output/results.txt
  
# Convenience target to attach to any session still running.
attach:
	$(TMUX) -S $(TMUX_SOCKET) attach
# Convenience target to kill any sessions
kill:
	$(TMUX) -S $(TMUX_SOCKET) -C kill-server
  
# Convenience to print out the current screen
show:
	echo capture-pane -p | $(TMUX) -S $(TMUX_SOCKET) -C attach