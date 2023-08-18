BUILD_DIR = ./build
ENTRY_POINT = 0xc0001500
AS = nasm
CC = gcc
LD = ld
LIB = -I lib/ -I lib/kernel/ -I lib/user/ -I kernel/ -I device/ -I thread/
ASFLAGS = -f elf
CFLAGS = -m32 -Wall $(LIB) -c -fno-builtin -W -Wstrict-prototypes -Wmissing-prototypes
LDFLAGS = -m elf_i386 -Ttext $(ENTRY_POINT) -e main -Map $(BUILD_DIR)/kernel.map
OBJS = $(BUILD_DIR)/main.o $(BUILD_DIR)/init.o $(BUILD_DIR)/interrupt.o \
      $(BUILD_DIR)/timer.o $(BUILD_DIR)/kernel.o $(BUILD_DIR)/print.o \
      $(BUILD_DIR)/debug.o $(BUILD_DIR)/memory.o $(BUILD_DIR)/bitmap.o \
      $(BUILD_DIR)/string.o $(BUILD_DIR)/thread.o $(BUILD_DIR)/list.o \
      $(BUILD_DIR)/switch.o $(BUILD_DIR)/console.o $(BUILD_DIR)/sync.o \
			$(BUILD_DIR)/keyboard.o $(BUILD_DIR)/ioqueue.o

############## 伪目标 ###############
.PHONY: mk_dir build disk clean all

all: mk_dir build disk

mk_dir:
	if [ ! -d $(BUILD_DIR) ];then mkdir $(BUILD_DIR);fi

build: $(BUILD_DIR)/kernel.bin $(BUILD_DIR)/mbr.bin $(BUILD_DIR)/loader.bin

disk: x86work.vhd

clean:
	cd $(BUILD_DIR) && rm -f ./*

.INTERMEDIATE: $(OBJS)
############## c 代码编译 ###############
$(BUILD_DIR)/main.o: kernel/main.c lib/kernel/print.h lib/stdint.h kernel/init.h kernel/memory.h thread/thread.h kernel/interrupt.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/init.o: kernel/init.c kernel/init.h kernel/memory.h lib/kernel/print.h lib/stdint.h kernel/interrupt.h device/timer.h device/keyboard.h thread/thread.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/interrupt.o: kernel/interrupt.c kernel/interrupt.h lib/stdint.h kernel/global.h lib/kernel/io.h lib/kernel/print.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/timer.o: device/timer.c device/timer.h lib/stdint.h lib/kernel/io.h lib/kernel/print.h thread/thread.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/debug.o: kernel/debug.c kernel/debug.h lib/kernel/print.h lib/stdint.h kernel/interrupt.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/bitmap.o: lib/kernel/bitmap.c lib/kernel/bitmap.h \
    	kernel/global.h lib/stdint.h lib/string.h lib/stdint.h \
     	lib/kernel/print.h kernel/interrupt.h kernel/debug.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/memory.o: kernel/memory.c kernel/memory.h lib/stdint.h lib/kernel/bitmap.h \
   	kernel/global.h kernel/global.h kernel/debug.h lib/kernel/print.h \
	lib/kernel/io.h kernel/interrupt.h lib/string.h lib/stdint.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/thread.o: thread/thread.c thread/thread.h lib/stdint.h \
        kernel/global.h lib/kernel/bitmap.h kernel/memory.h lib/string.h \
        lib/stdint.h lib/kernel/print.h kernel/interrupt.h kernel/debug.h lib/kernel/list.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/list.o: lib/kernel/list.c lib/kernel/list.h kernel/global.h lib/stdint.h \
        kernel/interrupt.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/console.o: device/console.c device/console.h lib/stdint.h \
        lib/kernel/print.h thread/sync.h lib/kernel/list.h kernel/global.h \
     	thread/thread.h thread/thread.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/sync.o: thread/sync.c thread/sync.h lib/kernel/list.h kernel/global.h \
       	lib/stdint.h thread/thread.h lib/string.h lib/stdint.h kernel/debug.h \
	kernel/interrupt.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/keyboard.o: device/keyboard.c device/keyboard.h lib/kernel/print.h \
        lib/stdint.h kernel/interrupt.h lib/kernel/io.h device/ioqueue.h \
	thread/thread.h lib/kernel/list.h kernel/global.h thread/sync.h \
      	thread/thread.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/ioqueue.o: device/ioqueue.c device/ioqueue.h lib/stdint.h thread/thread.h \
        lib/kernel/list.h kernel/global.h thread/sync.h thread/thread.h kernel/interrupt.h \
        kernel/debug.h
	$(CC) $(CFLAGS) $< -o $@
	
############## 汇编代码编译 ###############
$(BUILD_DIR)/mbr.bin: boot/mbr.S
	$(AS) -I boot/include/ -f bin $^ -o $@

$(BUILD_DIR)/loader.bin: boot/loader.S
	$(AS) -I boot/include/ -f bin $^ -o $@

$(BUILD_DIR)/print.o: lib/kernel/print.s
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/string.o: lib/string.c lib/string.h lib/stdint.h kernel/global.h \
	lib/stdint.h kernel/debug.h
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/kernel.o: kernel/kernel.S
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/switch.o: thread/switch.S
	$(AS) $(ASFLAGS) $< -o $@
############## 链接所有目标文件 #############
$(BUILD_DIR)/kernel.bin: $(OBJS)
	$(LD) $(LDFLAGS) $^ -o $@
############## 将代码写入硬盘 #############
x86work.vhd::	$(BUILD_DIR)/kernel.bin
	dd if=$^ of=$@ bs=512 count=200 seek=9 conv=notrunc

x86work.vhd::	$(BUILD_DIR)/loader.bin
	dd if=$^ of=$@ bs=512 count=4 seek=2 conv=notrunc

x86work.vhd::	$(BUILD_DIR)/mbr.bin
	dd if=$^ of=$@ bs=512 count=1 conv=notrunc