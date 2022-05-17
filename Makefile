OBJ_DIR   = ./obj
BIN_DIR   = ./bin
ENTRY_POINT = 0xc0001500

AS       = nasm 
CC       = gcc 
LD       = ld 

LIB1     = -I boot/include/
LIB2     = -I lib/

ASFLAGS  = -f elf 
CFLAGS   = -m32 -Wall -fno-builtin -W -Wstrict-prototypes -Wmissing-prototypes -fno-stack-protector  
LDFLAGS  = -m elf_i386 -Ttext ${ENTRY_POINT} -e main -Map ${BIN_DIR}/kernel.map 

OBJS = ${OBJ_DIR}/main.o ${OBJ_DIR}/init.o ${OBJ_DIR}/print.o ${OBJ_DIR}/kernel.o              \
	   ${OBJ_DIR}/interrupt.o ${OBJ_DIR}/timer.o ${OBJ_DIR}/debug.o ${OBJ_DIR}/string.o        \
	   ${OBJ_DIR}/bitmap.o ${OBJ_DIR}/memory.o ${OBJ_DIR}/thread.o ${OBJ_DIR}/switch.o         \
	   ${OBJ_DIR}/list.o ${OBJ_DIR}/sync.o ${OBJ_DIR}/console.o ${OBJ_DIR}/keyboard.o          \
	   ${OBJ_DIR}/ioqueue.o ${OBJ_DIR}/tss.o ${OBJ_DIR}/process.o ${OBJ_DIR}/syscall.o   	   \
	   ${OBJ_DIR}/syscall-init.o ${OBJ_DIR}/stdio.o ${OBJ_DIR}/stdio-kernel.o ${OBJ_DIR}/ide.o \
	   ${OBJ_DIR}/inode.o ${OBJ_DIR}/file.o ${OBJ_DIR}/dir.o ${OBJ_DIR}/fs.o ${OBJ_DIR}/fork.o \
	   ${OBJ_DIR}/shell.o ${OBJ_DIR}/assert.o ${OBJ_DIR}/buildin_cmd.o ${OBJ_DIR}/exec.o       \
	   ${OBJ_DIR}/wait_exit.o ${OBJ_DIR}/pipe.o

.PHONY: mbr loader kernel run clean all

mk_dir:
	if [ ! -d ${OBJ_DIR} ]; then mkdir ${OBJ_DIR};fi
	if [ ! -d ${BIN_DIR} ]; then mkdir ${BIN_DIR};fi

mbr: boot/mbr.S 
	${AS} ${LIB1} -o ${BIN_DIR}/mbr.bin $^ && dd if=${BIN_DIR}/mbr.bin of=/home/os/myOS/bochs/hd1G.img bs=512 count=1 seek=0 conv=notrunc

loader: boot/loader.S 
	${AS} ${LIB1} -o ${BIN_DIR}/loader.bin $^ && dd if=${BIN_DIR}/loader.bin of=/home/os/myOS/bochs/hd1G.img bs=512 count=3 seek=2  conv=notrunc

kernel: ${OBJS}
	${LD} ${LDFLAGS} -o ${BIN_DIR}/kernel.bin $^ && dd if=${BIN_DIR}/kernel.bin of=/home/os/myOS/bochs/hd1G.img bs=512 count=200 seek=9 conv=notrunc 

${OBJ_DIR}/main.o: kernel/main.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/init.o: kernel/init.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^

${OBJ_DIR}/print.o: kernel/print.S 
	${AS} ${ASFLAGS} ${LIB2} -o $@ $^  

${OBJ_DIR}/kernel.o: kernel/kernel.S
	${AS} ${ASFLAGS} ${LIB2} -o $@ $^ 

${OBJ_DIR}/interrupt.o: kernel/interrupt.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/timer.o: device/timer.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^

${OBJ_DIR}/debug.o: kernel/debug.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^

${OBJ_DIR}/string.o: kernel/string.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/bitmap.o: kernel/bitmap.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/memory.o: kernel/memory.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/thread.o: thread/thread.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 
${OBJ_DIR}/switch.o: thread/switch.S   
	${AS} ${ASFLAGS} ${LIB2} -o $@ $^ 

${OBJ_DIR}/list.o: kernel/list.c   
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/sync.o: thread/sync.c    
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/console.o: device/console.c    
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/keyboard.o: device/keyboard.c     
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/ioqueue.o: device/ioqueue.c     
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/tss.o: userprog/tss.c     
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/process.o: userprog/process.c    
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/syscall.o: user/syscall.c     
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/syscall-init.o: userprog/syscall-init.c    
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/stdio.o: kernel/stdio.c    
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/stdio-kernel.o: kernel/stdio-kernel.c     
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/ide.o: device/ide.c   
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/inode.o: fs/inode.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/file.o: fs/file.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/dir.o: fs/dir.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/fs.o: fs/fs.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/fork.o: userprog/fork.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/shell.o: shell/shell.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/assert.o: user/assert.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/buildin_cmd.o: shell/buildin_cmd.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/exec.o: userprog/exec.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/wait_exit.o: userprog/wait_exit.c  
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

${OBJ_DIR}/pipe.o: shell/pipe.c 
	${CC} ${CFLAGS} ${LIB2} -o $@ -c $^ 

run:
	./bochs/bin/bochs -f ./bochs/bochsrc.disk 

all: mk_dir mbr loader kernel run 

clean:
	rm -rf obj bin 

