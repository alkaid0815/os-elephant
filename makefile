all: mbr loader kernel disk

target/mbr.bin: boot/mbr.S
	nasm -I boot/include/ -f bin boot/mbr.S -o target/mbr.bin

target/loader.bin: boot/loader.S
	nasm -I boot/include/ -f bin boot/loader.S -o target/loader.bin

x86work.vhd::	target/kernel.bin
	dd if=target/kernel.bin of=x86work.vhd bs=512 count=200 seek=9 conv=notrunc

x86work.vhd::	target/loader.bin
	dd if=target/loader.bin of=x86work.vhd bs=512 count=4 seek=2 conv=notrunc

x86work.vhd::	target/mbr.bin
	dd if=target/mbr.bin of=x86work.vhd bs=512 count=1 conv=notrunc

target/kernel.bin: target/main.o target/print.o target/init.o target/interrupt.o target/kernel.o target/timer.o
	ld -m elf_i386 -Ttext 0xc0001500 -e main -o target/kernel.bin target/main.o target/init.o target/interrupt.o target/print.o target/kernel.o target/timer.o	

target/main.o: kernel/main.c lib/stdint.h lib/kernel/print.h
	gcc -m32 -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -o target/main.o kernel/main.c

target/print.o: lib/kernel/print.s
	nasm -f elf -o target/print.o lib/kernel/print.S

target/timer.o: device/timer.c
	gcc -m32 -I lib/kernel/ -I lib/ -c -fno-builtin -o target/timer.o device/timer.c

target/init.o: kernel/init.c
	gcc -m32 -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -o target/init.o kernel/init.c

target/interrupt.o: kernel/interrupt.c
	gcc -m32 -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -o target/interrupt.o kernel/interrupt.c

target/kernel.o: kernel/kernel.S
	nasm -f elf -o target/kernel.o kernel/kernel.S

.PHONY: clean
clean:
	find . -name "*.o" -or -name "*.bin" | xargs rm -rf

.PHONY: kernel
kernel: target/kernel.bin

.PHONY: disk
disk: x86work.vhd

.PHONY: mbr
mbr: target/mbr.bin

.PHONY: loader
loader: target/loader.bin