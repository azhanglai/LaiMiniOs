[TOC]

### 1、 中断是什么，为什么要有中断

**1.1** CPU获知了计算机中发生的某些事，CPU暂停正在执行的程序，转而去执行处理该事件的程序，当这段程序执行完毕后，CPU继续执行刚才的程序。整个过程称为中断处理，也称中断。

**1.2** 中断虽然是打断的意思，但它恰恰是提升整个系统利用率最有效的方式。因为有了中断，系统才能并发运行。

**1.3** “没有中断，操作系统几乎什么都做不了，操作系统是中断驱动的"

### 2、 中断分类

**2.1** 外部中断：来自CPU外部的中断，而外部的中断源必须来自某个硬件，故外部中断又称为硬件中断。CPU提供统一的接口作为中断信号的公共线路，所有来自外设的的中断信号都共享公共线路连接的CPU。CPU提供了两条信号线（INTR， NMI），外部硬件的中断是通过两根信号线通知CPU的。![img](https://s2.loli.net/2022/02/13/Sf6GRyXUdVA1Hqb.png)

**2.2** 内部中断：软中断和异常。软中断是由软件主动发起的中断，来自软件，故称为软中断。如系统调用（int 0x80）,调试断电指令（int 3）。异常是指令执行期间CPU内部产生的错误引起的。如除0错误，缺页异常

### 3、 中断描述符表（IDT）

**3.1** 中断描述符表是保护模式下用于存储中断处理程序入口的表，当CPU接收一个中断时，需要用中断向量在中断描述符表中检索对应的描述符，在该描述符中找到中断处理程序的起始地址，然后执行中断处理程序。

**3.2** 中断描述符表里面的门描述符：任务门描述符，中断门描述符，陷阱门描述符![img](https://s2.loli.net/2022/02/13/lNr95eHEQmROPvU.png)![img](https://s2.loli.net/2022/02/13/mLkMp8Ia573GZBV.png)

**3.3** CPU内部有个中断描述符表寄存器（IDTR），该寄存器分为两个部分：0 ~ 15位是表界限，第16 ~ 47位是IDT的基地址。

![img](https://s2.loli.net/2022/02/13/wOcuAnD31BS9r6X.png)

### 4、 中断处理过程及保护

**4.1** CPU外部中断：外部设备中断有中断代理芯片（8259A）接收，处理后将该中断的中断向量号发送到CPU；

**4.2** CPU内部中断：CPU执行该中断向量号对应的中断处理程序。

1.  处理器根据中断向量号定位中断门描述符。
2.  处理器进行特权级检查。当前特权级CPL必须在门描述符DPL和门中目标代码段DPL之间（数值上目标代码段DPL < CPL <= 门DPL），为了防止位于3特权级下的用户程序主动调用某些只为内核服务的例程。
3.  执行中断处理程序。特权级检查通过后，将门描述符目标代码段选择子加载到CS，把门描述符中中断处理程序 偏移地址加载到EIP，开始执行中断处理程序。![image-20220213180212045](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20220213180212045.png)

### 5、 可编程中断控制器8259A

**5.1** 8259A的作用是负责所有来自外设的中断，其中就包括来自时钟的中断，键盘的中断等。8259A用于管理和控制可屏蔽中断，它表现在屏蔽外设中断，对他们实行优先级判决，向CPU提供中断向量号等功能。

**5.2** 8259A只可以管理8个中断，可以采用级联方式，将多片8259A芯片连在一起，最多可级联9个，级联时只有一片是主片master，其实的均为从片slave。从片的中断只能传递给主片，再由主片传递给CPU，只有主片才会向CPU发送INT中断信号。![img](https://s2.loli.net/2022/02/13/zxHOjGsiAJ59CYv.png)

**5.3**  8295A内部结构逻辑

![img](https://s2.loli.net/2022/02/13/nCviUE9e8YmlL5S.png)

**5.4**  8295A的编程。在8259A内部有两组寄存器，一组是初始化命令寄存器组，用来保存初始化命令字（ICW），ICW共4个。另一组寄存器是操作命令寄存器组，用来保持操作命令字（OCW），OCW共3个。8295A的编程分初始化和操作两部分。一部分是用ICW做初始化，用来确定是否需要级联，设置起始中断向量号，设置中断结束模式。另一部分是用OCW来操作控制8259A，中断屏蔽和中断结束是通过往8259A端口发送OCW实现的。

### 6、 中断初始化

**6.1** 初始化中断描述符表（IDT）

1. 创建中断门描述符。

   ​		输入: &idt[i]，第i个门描述符； attr: 门描述符属性； func:中断处理函数入口地址（代码段地址，段内偏移地址）

2. 异常中断名称初始化并注册通用的中断处理函数

   ​		中断处理函数地址注册到中断处理程序指针数组（idt_table）中

   ​		idt_table[i] = intr_handler

   ​		异常名称初始化 intr_name[i] = "***"

3. 初始化可编程中断控制器8259A

   ​		初始化主片4个命令字（ICW1~ICW4）

   ​		初始化从片4个命令字（ICW1~ICW4）		

   ​		操作命令字（OCW），主片上打开的中断有IRQ0的时钟，IRQ1的键盘和级联从片的IRQ2，其它全部关闭。

   ​		从片上的	IRQ14，此引脚接收硬盘控制器的中断

4. 加载IDT

   ​		idt_operand = idt_limit | idt_base << 16

   ​		lidt  idt_operand

~~~c
/* 完成有关中断的所有初始化工作 */
void idt_init() {
   	idt_desc_init();	   	// 初始化中断描述符表
   	exception_init();	   	// 异常名初始化并注册通常的中断处理函数
   	pic_init();		   		// 初始化8259A
   	// 加载idt 
   	uint64_t idt_operand = ((sizeof(idt) - 1) | ((uint64_t)(uint32_t)idt << 16));
   	asm volatile("lidt %0" : : "m" (idt_operand));
}
~~~

### 7、 可编程定时器8253

**7.1** 计算机中的时钟，大致分为两大类：内部时钟和外部时钟。

**7.2** 内部时钟是指处理器中内部元件，如运算器、控制器的工作时序，主要用于控制、同步内部工作过程的步调。内部时钟是由晶体振荡器产生的，简称晶振，它位于主板上，其频率经过分频后就是主板的外频，处理器和南北桥之间的通信基于外频。Intel处理器将外频乘以某个倍数后便称为主频。处理器取指令、执行指令中所消耗的时钟周期，都是基于主频。

**7.3** 外部时钟是指处理器与外部设备或外部设备之间通信时采用的一种时序，比如IO接口和处理器之间在A/D转换时的工作时序、两个串口设备之间进行数据传输时也要事先同步时钟等。

**7.4** 8253初始化步骤：①往控制字寄存器端口0x43中写入控制字 ②在所指定使用的计数器端口中写入计数初值

### 8、 初始化8253定时器

~~~h
// 头文件 timer.h
#ifndef __DEVICE_TIME_H
#define __DEVICE_TIME_H

#include "stdint.h"
void timer_init(void);

#endif
~~~

~~~c
// timer.c文件

#include "timer.h"
#include "io.h"
#include "print.h"
#include "interrupt.h"
#include "thread.h"
#include "debug.h"

#define IRQ0_FREQUENCY	   	100
#define INPUT_FREQUENCY	   	1193180
#define COUNTER0_VALUE	   	INPUT_FREQUENCY / IRQ0_FREQUENCY
#define CONTRER0_PORT	   	0x40
#define COUNTER0_NO	   		0
#define COUNTER_MODE	   	2
#define READ_WRITE_LATCH   	3
#define PIT_CONTROL_PORT   	0x43

/* 把操作的计数器counter_no、读写锁属性rwl、计数器模式counter_mode写入模式控制寄存器并赋予初始值counter_value */
static void frequency_set(uint8_t counter_port, \
			  				uint8_t counter_no, \
			  				uint8_t rwl, \
			  				uint8_t counter_mode, \
			  				uint16_t counter_value) 
{
	// 往控制字寄存器端口0x43中写入控制字 
   	outb(PIT_CONTROL_PORT, (uint8_t)(counter_no << 6 | rwl << 4 | counter_mode << 1));
	// 先写入counter_value的低8位 
   	outb(counter_port, (uint8_t)counter_value);
	// 再写入counter_value的高8位 
   	outb(counter_port, (uint8_t)counter_value >> 8);
}

/* 初始化PIT8253 */
void timer_init() {
   	put_str("timer_init start\n");
   	// 设置8253的定时周期,也就是发中断的周期
   	frequency_set(CONTRER0_PORT, COUNTER0_NO, READ_WRITE_LATCH, COUNTER_MODE, COUNTER0_VALUE);
   	put_str("timer_init done\n");
}

~~~

### 9、 中断代码（kernel.S、interrupt.c）代码实现

**9.1**  kernel.S ：实现中断处理程序。实现中断处理程序入口地址数组intr_entry_table；调用idt_table中的中断处理函数和调用int 0x80中断，syscall_table中的系统调用函数；中断结束intr_exit恢复上下文环境

**9.2**  interrupt.c：中断初始化。构建中断描述表，注册中断处理函数（ide_table）,初始化8295A，加载IDT，实现中断开关处理函数。

~~~assembly
[bits 32]
%define ERROR_CODE nop		 
%define ZERO push 0		 

extern idt_table 				; idt_table是C中注册的中断处理程序数组

section .data
global intr_entry_table
intr_entry_table:

%macro VECTOR 2
section .text
intr%1entry:		 	; 每个中断处理程序都要压入中断向量号,所以一个中断类型一个中断处理程序.
   	%2				 	; 中断若有错误码会压在eip后面 
; 以下是保存上下文环境
   	push ds
   	push es
   	push fs
   	push gs
   	pushad			 	; PUSHAD指令压入32位寄存器,其入栈顺序是: EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI

   	; 如果是从片上进入的中断,除了往从片上发送EOI外,还要往主片上发送EOI 
   	mov al,0x20 		; 中断结束命令EOI
   	out 0xa0,al        	; 向从片发送
   	out 0x20,al        	; 向主片发送
   	push %1			 	; 不管idt_table中的目标程序是否需要参数,都一律压入中断向量号.
  	call [idt_table + %1*4]  	; 调用idt_table中的C版本中断处理函数
   	jmp intr_exit

section .data
   	dd    intr%1entry 	; 存储各个中断入口程序的地址，形成intr_entry_table数组
%endmacro

section .text
global intr_exit
intr_exit:	     
; 以下是恢复上下文环境
   	add esp, 4			   ; 跳过中断号
   	popad
   	pop gs
   	pop fs
   	pop es
   	pop ds
   	add esp, 4			   ; 跳过error_code
   	iretd

VECTOR 0x00, ZERO
VECTOR 0x01, ZERO
VECTOR 0x02, ZERO
VECTOR 0x03, ZERO 
VECTOR 0x04, ZERO
VECTOR 0x05, ZERO
VECTOR 0x06, ZERO
VECTOR 0x07, ZERO 
VECTOR 0x08, ERROR_CODE
VECTOR 0x09, ZERO
VECTOR 0x0a, ERROR_CODE
VECTOR 0x0b, ERROR_CODE 
VECTOR 0x0c, ZERO
VECTOR 0x0d, ERROR_CODE
VECTOR 0x0e, ERROR_CODE
VECTOR 0x0f, ZERO 
VECTOR 0x10, ZERO
VECTOR 0x11, ERROR_CODE
VECTOR 0x12, ZERO
VECTOR 0x13, ZERO 
VECTOR 0x14, ZERO
VECTOR 0x15, ZERO
VECTOR 0x16, ZERO
VECTOR 0x17, ZERO 
VECTOR 0x18, ERROR_CODE
VECTOR 0x19, ZERO
VECTOR 0x1a, ERROR_CODE
VECTOR 0x1b, ERROR_CODE 
VECTOR 0x1c, ZERO
VECTOR 0x1d, ERROR_CODE
VECTOR 0x1e, ERROR_CODE
VECTOR 0x1f, ZERO 
VECTOR 0x20, ZERO	;时钟中断对应的入口
VECTOR 0x21, ZERO	;键盘中断对应的入口
VECTOR 0x22, ZERO	;级联用的
VECTOR 0x23, ZERO	;串口2对应的入口
VECTOR 0x24, ZERO	;串口1对应的入口
VECTOR 0x25, ZERO	;并口2对应的入口
VECTOR 0x26, ZERO	;软盘对应的入口
VECTOR 0x27, ZERO	;并口1对应的入口
VECTOR 0x28, ZERO	;实时时钟对应的入口
VECTOR 0x29, ZERO	;重定向
VECTOR 0x2a, ZERO	;保留
VECTOR 0x2b, ZERO	;保留
VECTOR 0x2c, ZERO	;ps/2鼠标
VECTOR 0x2d, ZERO	;fpu浮点单元异常
VECTOR 0x2e, ZERO	;硬盘
VECTOR 0x2f, ZERO	;保留

; 0x80号中断 
[bits 32]
extern syscall_table
section .text
global syscall_handler
syscall_handler:
; 1保存上下文环境
   	push 0			    ; 压入0, 使栈中格式统一
   	push ds
   	push es
  	push fs
   	push gs
   	pushad			    			 
   	push 0x80			; 此位置压入0x80也是为了保持统一的栈格式

; 2为系统调用子功能传入参数
   	push edx			; 系统调用中第3个参数
   	push ecx			; 系统调用中第2个参数
   	push ebx		    ; 系统调用中第1个参数

; 3调用子功能处理函数
   	call [syscall_table + eax*4] 	; 编译器会在栈中根据C函数声明匹配正确数量的参数
   	add esp, 12			    		; 跨过上面的三个参数

; 4将call调用后的返回值存入待当前内核栈中eax的位置
   	mov [esp + 8*4], eax	
   	jmp intr_exit		    		; intr_exit返回,恢复上下文


~~~



~~~c
// 头文件interrupt.h
#ifndef __KERNEL_INTERRUPT_H
#define __KERNEL_INTERRUPT_H
#include "stdint.h"

typedef void* intr_handler;
void idt_init(void);

// 定义中断的两种状态
enum intr_status {		 // 中断状态
    INTR_OFF,			 // 中断关闭
    INTR_ON		         // 中断打开
};

enum intr_status intr_get_status(void);
enum intr_status intr_set_status (enum intr_status);
enum intr_status intr_enable (void);
enum intr_status intr_disable (void);
void register_handler(uint8_t vector_no, intr_handler function);

#endif
~~~

~~~c
// interrupt.c 文件

#include "interrupt.h"
#include "stdint.h"
#include "global.h"
#include "io.h"
#include "print.h"

#define PIC_M_CTRL 0x20	       // 这里用的可编程中断控制器是8259A,主片的控制端口是0x20
#define PIC_M_DATA 0x21	       // 主片的数据端口是0x21
#define PIC_S_CTRL 0xa0	       // 从片的控制端口是0xa0
#define PIC_S_DATA 0xa1	       // 从片的数据端口是0xa1

#define IDT_DESC_CNT 0x81      // 目前总共支持的中断数

#define EFLAGS_IF   0x00000200       // eflags寄存器中的if位为1
#define GET_EFLAGS(EFLAG_VAR) asm volatile("pushfl; popl %0" : "=g" (EFLAG_VAR))

extern uint32_t syscall_handler(void);

/* 中断门描述符结构体 */
struct gate_desc {
    uint16_t    func_offset_low_word;
   	uint16_t    selector;
   	uint8_t     dcount;   
   	uint8_t     attribute;
   	uint16_t    func_offset_high_word;
};

static void make_idt_desc(struct gate_desc *p_gdesc, uint8_t attr, intr_handler function);
static struct gate_desc idt[IDT_DESC_CNT]; 				// idt是中断描述符表,本质上就是个中断门描述符数组

char *intr_name[IDT_DESC_CNT];		     				// 用于保存异常的名字
intr_handler idt_table[IDT_DESC_CNT]; 					// 定义中断处理程序数组
extern intr_handler intr_entry_table[IDT_DESC_CNT]; 	// 声明引用定义在kernel.S中的中断处理函数入口数组

/* 初始化可编程中断控制器8259A */
static void pic_init(void) {
   	// 初始化主片 
	outb (PIC_M_CTRL, 0x11);   // ICW1: 边沿触发,级联8259, 需要ICW4.
   	outb (PIC_M_DATA, 0x20);   // ICW2: 起始中断向量号为0x20,也就是IR[0-7] 为 0x20 ~ 0x27.
   	outb (PIC_M_DATA, 0x04);   // ICW3: IR2接从片. 
   	outb (PIC_M_DATA, 0x01);   // ICW4: 8086模式, 正常EOI

   	// 初始化从片 
   	outb (PIC_S_CTRL, 0x11);    // ICW1: 边沿触发,级联8259, 需要ICW4.
   	outb (PIC_S_DATA, 0x28);    // ICW2: 起始中断向量号为0x28,也就是IR[8-15] 为 0x28 ~ 0x2F.
   	outb (PIC_S_DATA, 0x02);    // ICW3: 设置从片连接到主片的IR2引脚
   	outb (PIC_S_DATA, 0x01);    // ICW4: 8086模式, 正常EOI
   
  	// IRQ2用于级联从片,必须打开,否则无法响应从片上的中断
  	// 主片上打开的中断有IRQ0的时钟,IRQ1的键盘和级联从片的IRQ2,其它全部关闭 
   	outb (PIC_M_DATA, 0xf8);
	// 打开从片上的IRQ14,此引脚接收硬盘控制器的中断 
   	outb (PIC_S_DATA, 0xbf);
   	put_str("   pic_init done\n");
}

/* 创建中断门描述符 */
static void make_idt_desc(struct gate_desc *p_gdesc, uint8_t attr, intr_handler function) { 
	p_gdesc->func_offset_low_word = (uint32_t)function & 0x0000FFFF;
   	p_gdesc->selector = SELECTOR_K_CODE;
   	p_gdesc->dcount = 0;
   	p_gdesc->attribute = attr;
   	p_gdesc->func_offset_high_word = ((uint32_t)function & 0xFFFF0000) >> 16;
}

/* 初始化中断描述符表 */
static void idt_desc_init(void) {
   	int i, lastindex = IDT_DESC_CNT - 1;
   	for (i = 0; i < IDT_DESC_CNT; i++) {
      	make_idt_desc(&idt[i], IDT_DESC_ATTR_DPL0, intr_entry_table[i]); 
   	}
    // 单独处理系统调用,系统调用对应的中断门dpl为3, 中断处理程序为单独的syscall_handler
   	make_idt_desc(&idt[lastindex], IDT_DESC_ATTR_DPL3, syscall_handler);
   	put_str("   idt_desc_init done\n");
}

/* 通用的中断处理函数,一般用在异常出现时的处理 */
static void general_intr_handler(uint8_t vec_nr) {
    // 0x2f是从片8259A上的最后一个irq引脚，保留
    // IRQ7和IRQ15会产生伪中断(spurious interrupt),无须处理。
   	if (vec_nr == 0x27 || vec_nr == 0x2f) {	
      	return;		
   	}
  	// 将光标置为0,从屏幕左上角清出一片打印异常信息的区域,方便阅读 
   	set_cursor(0);
   	int cursor_pos = 0;
   	while(cursor_pos < 320) {
      	put_char(' ');
      	cursor_pos++;
   	}
   	set_cursor(0);	 	// 重置光标为屏幕左上角
  	put_str("!!!!!!!      excetion message begin  !!!!!!!!\n");
   	set_cursor(88);		
   	put_str(intr_name[vec_nr]);
    // 若为Pagefault,将缺失的地址打印出来并悬停
   	if (vec_nr == 14) {	  
      	int page_fault_vaddr = 0; 
        // cr2是存放造成page_fault的地址
      	asm ("movl %%cr2, %0" : "=r" (page_fault_vaddr));	  	
      	put_str("\npage fault addr is 0x");put_int(page_fault_vaddr); 
   	}
   	put_str("\n!!!!!!!      excetion message end    !!!!!!!!\n");
  	// 能进入中断处理程序就表示已经处在关中断情况下,
  	// 不会出现调度进程的情况。故下面的死循环不会再被中断。
   	while(1);
}

/* 完成一般中断处理函数注册及异常名称注册 */
static void exception_init(void) {			   
   	int i;
  	for (i = 0; i < IDT_DESC_CNT; i++) {
      	idt_table[i] = general_intr_handler; 	// 默认为general_intr_handler。
      	intr_name[i] = "unknown";				// 先统一赋值为unknown 
   	}
   	intr_name[0] = "#DE Divide Error";
   	intr_name[1] = "#DB Debug Exception";
   	intr_name[2] = "NMI Interrupt";
   	intr_name[3] = "#BP Breakpoint Exception";
   	intr_name[4] = "#OF Overflow Exception";
   	intr_name[5] = "#BR BOUND Range Exceeded Exception";
   	intr_name[6] = "#UD Invalid Opcode Exception";
   	intr_name[7] = "#NM Device Not Available Exception";
   	intr_name[8] = "#DF Double Fault Exception";
   	intr_name[9] = "Coprocessor Segment Overrun";
   	intr_name[10] = "#TS Invalid TSS Exception";
   	intr_name[11] = "#NP Segment Not Present";
   	intr_name[12] = "#SS Stack Fault Exception";
   	intr_name[13] = "#GP General Protection Exception";
   	intr_name[14] = "#PF Page-Fault Exception";
   	// intr_name[15] 第15项是intel保留项，未使用
   	intr_name[16] = "#MF x87 FPU Floating-Point Error";
   	intr_name[17] = "#AC Alignment Check Exception";
   	intr_name[18] = "#MC Machine-Check Exception";
   	intr_name[19] = "#XF SIMD Floating-Point Exception";
}

/* 开中断并返回开中断前的状态 */
enum intr_status intr_enable() {
    enum intr_status old_status;
   	if (INTR_ON == intr_get_status()) {
      	old_status = INTR_ON;
      	return old_status;
   	} else {
      	old_status = INTR_OFF;
      	asm volatile("sti");	 			// 开中断,sti指令将IF位置1
      	return old_status;
   	}
}

/* 关中断,并且返回关中断前的状态 */
enum intr_status intr_disable() {     
   	enum intr_status old_status;
   	if (INTR_ON == intr_get_status()) {
      	old_status = INTR_ON;
      	asm volatile("cli" : : : "memory"); // 关中断,cli指令将IF位置0
      	return old_status;
   } else {
      	old_status = INTR_OFF;
      	return old_status;
   }
}

/* 将中断状态设置为status */
enum intr_status intr_set_status(enum intr_status status) {
	return status & INTR_ON ? intr_enable() : intr_disable();
}

/* 获取当前中断状态 */
enum intr_status intr_get_status() {
   	uint32_t eflags = 0; 
   	GET_EFLAGS(eflags);
   	return (EFLAGS_IF & eflags) ? INTR_ON : INTR_OFF;
}

/* 在中断处理程序数组第vector_no个元素中注册安装中断处理程序function */
void register_handler(uint8_t vector_no, intr_handler function) {
   	idt_table[vector_no] = function; 
}

/* 完成有关中断的所有初始化工作 */
void idt_init() {
   	put_str("idt_init start\n");
   	idt_desc_init();	   	// 初始化中断描述符表
   	exception_init();	   	// 异常名初始化并注册通常的中断处理函数
   	pic_init();		   		// 初始化8259A
   	// 加载idt 
   	uint64_t idt_operand = ((sizeof(idt) - 1) | ((uint64_t)(uint32_t)idt << 16));
   	asm volatile("lidt %0" : : "m" (idt_operand));
   	put_str("idt_init done\n");
}

~~~



