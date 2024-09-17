# Compiler and flags
CC = gcc
MPICC = mpicc
CFLAGS = -Wall -Wextra -O2
LDFLAGS = -lm

# Source files
SRCS_SERIAL = mandelbrot_serial.c
SRCS_MPI = mandelbrot_mpi.c

# Object files
OBJS_SERIAL = $(SRCS_SERIAL:.c=.o)
OBJS_MPI = $(SRCS_MPI:.c=.o)

# Executable names
TARGET_SERIAL = mandelbrot_serial
TARGET_MPI = mandelbrot_mpi

# Default target
all: $(TARGET_SERIAL) $(TARGET_MPI)

# Rule to build the serial version
$(TARGET_SERIAL): $(OBJS_SERIAL)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# Rule to build the MPI version
$(TARGET_MPI): $(OBJS_MPI)
	$(MPICC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

# Rule to compile serial C files to object files
$(OBJS_SERIAL): $(SRCS_SERIAL)
	$(CC) $(CFLAGS) -c $< -o $@

# Rule to compile MPI C files to object files
$(OBJS_MPI): $(SRCS_MPI)
	$(MPICC) $(CFLAGS) -c $< -o $@

# Clean up build files
clean:
	rm -f $(OBJS_SERIAL) $(OBJS_MPI) $(TARGET_SERIAL) $(TARGET_MPI)
	rm -f *.pgm

# Phony targets
.PHONY: all clean
