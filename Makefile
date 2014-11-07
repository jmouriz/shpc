PROGRAM=shpc
CC=gcc
FLAGS=-Wall

all: $(PROGRAM)

package: all clean
	# todo

clean:
	-rm tests/*.x
	-rm $(PROGRAM).o

test: all
	-./$(PROGRAM) -i tests/hello.sh -o tests/hello.x
	-tests/hello.x
	-./$(PROGRAM) -i tests/test.sh -o tests/test.x
	-tests/test.x
	-./$(PROGRAM) -i tests/args.sh -o tests/args.x
	-tests/args.x this is a test
	-./$(PROGRAM) -i tests/mount-vdi.bash -o tests/mount-vdi.x -s /bin/bash

$(PROGRAM): $(PROGRAM).o
	$(CC) $^ -o $@

$(PROGRAM).o: $(PROGRAM).c
	$(CC) -c $^ -o $@ $(FLAGS)
