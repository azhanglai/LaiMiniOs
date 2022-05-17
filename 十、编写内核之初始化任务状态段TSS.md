[TOC]

### 1、TSS

**1.1**  任务状态段（TSS），它是处理器在硬件上原生支持多任务的一种实现方式；TSS是每个任务都有的结构，它用于一个任务的标识，相当于任务的身份证，程序拥有此结构才能运行，这是处理器硬件上用于任务管理的系统结构，处理器能够识别其中每一个字段。在没有操作系统的情况下，可以认为进程就是任务。

![img](https://s2.loli.net/2022/02/15/YK4SNw9ihsVE53Z.png)

**1.2** 单核CPU要想实现多任务，唯一的方案就是多个任务共享一个CPU，也就是只能让CPU在多个任务间轮转，让所有任务轮流使用CPU。当加载新任务时，CPU自动把当前的任务的状态存入当前任务的TSS，然后将新任务TSS中的数据载入到对应的寄存器，这就实现了任务切换。任务切换的本质就是TSS的换来换去。

**1.3** CPU中有一个专门存储TSS信息的寄存器，这就是TR寄存器，它始终指向当前正在运行的任务。“在CPU眼里”任务切换的实质就是TR寄存器指向不同的TSS。总之在CPU眼里任务切换就是TSS换来换去，只是CPU的美好愿景，Linux并未这么做。

**1.4** TSS 描述符，需要在GDT中注册。![img](https://s2.loli.net/2022/02/15/BQ1jDS4qwvLnJbZ.png)



**1.5** TSS、LDT、GDT全景图

 ![img](https://s2.loli.net/2022/02/15/KsyfSjvODgemtxk.png)

### 2、现代操作系统采用的任务切换方式

**2.1** 效仿Linux的任务切换方法。Linux对TSS的操作是一次性加载TSS到TR，之后不断修改同一个TSS的内容，不再进行重复加载操作。Linux在TSS中只初始化了SS0，esp0和I/O位图字段，除此之外TSS便没用了，就是空架子，不再做保持任务状态之用。

**2.2** CPU自动从当前任务的TSS中获取SS0和esp0字段的值作为0特权级的栈，然后“手动“执行一系列的push压栈操作，将任务的状态保存在0特权级中，就是TSS中SS0和esp0所指向的栈。

**2.3** linux中任务切换不使用call和jmp指令，避免了任务切换的低效。

### 3、更新GDT

~~~c
#ifndef __KERNEL_GLOBAL_H
#define __KERNEL_GLOBAL_H
#include "stdint.h"


// ----------------  GDT描述符属性  ----------------
#define	DESC_G_4K    1
#define	DESC_D_32    1
#define DESC_L	     0	
#define DESC_AVL     0	
#define DESC_P	     1
#define DESC_DPL_0   0
#define DESC_DPL_1   1
#define DESC_DPL_2   2
#define DESC_DPL_3   3

#define DESC_S_CODE	1
#define DESC_S_DATA	DESC_S_CODE
#define DESC_S_SYS	0
#define DESC_TYPE_CODE	8	// x=1,c=0,r=0,a=0 代码段是可执行的,非依从的,不可读的,已访问位a清0.  
#define DESC_TYPE_DATA  2	// x=0,e=0,w=1,a=0 数据段是不可执行的,向上扩展的,可写的,已访问位a清0.
#define DESC_TYPE_TSS   9	// B位为0,不忙


#define	 RPL0  0
#define	 RPL1  1
#define	 RPL2  2
#define	 RPL3  3

#define TI_GDT 0
#define TI_LDT 1

#define SELECTOR_K_CODE	   ((1 << 3) + (TI_GDT << 2) + RPL0)
#define SELECTOR_K_DATA	   ((2 << 3) + (TI_GDT << 2) + RPL0)
#define SELECTOR_K_STACK   SELECTOR_K_DATA 
#define SELECTOR_K_GS	   ((3 << 3) + (TI_GDT << 2) + RPL0)
/* 第3个段描述符是显存,第4个是tss */
#define SELECTOR_U_CODE	   ((5 << 3) + (TI_GDT << 2) + RPL3)
#define SELECTOR_U_DATA	   ((6 << 3) + (TI_GDT << 2) + RPL3)
#define SELECTOR_U_STACK   SELECTOR_U_DATA

#define GDT_ATTR_HIGH		 ((DESC_G_4K << 7) + (DESC_D_32 << 6) + (DESC_L << 5) + (DESC_AVL << 4))
#define GDT_CODE_ATTR_LOW_DPL3	 ((DESC_P << 7) + (DESC_DPL_3 << 5) + (DESC_S_CODE << 4) + DESC_TYPE_CODE)
#define GDT_DATA_ATTR_LOW_DPL3	 ((DESC_P << 7) + (DESC_DPL_3 << 5) + (DESC_S_DATA << 4) + DESC_TYPE_DATA)


//---------------  TSS描述符属性  ------------
#define TSS_DESC_D  0 

#define TSS_ATTR_HIGH ((DESC_G_4K << 7) + (TSS_DESC_D << 6) + (DESC_L << 5) + (DESC_AVL << 4) + 0x0)
#define TSS_ATTR_LOW ((DESC_P << 7) + (DESC_DPL_0 << 5) + (DESC_S_SYS << 4) + DESC_TYPE_TSS)
#define SELECTOR_TSS ((4 << 3) + (TI_GDT << 2 ) + RPL0)


struct gdt_desc {
   uint16_t limit_low_word;
   uint16_t base_low_word;
   uint8_t  base_mid_byte;
   uint8_t  attr_low_byte;
   uint8_t  limit_high_attr_high;
   uint8_t  base_high_byte;
}; 


#endif

~~~



### 4、tss.c代码实现

**4.1** update_tss_esp: 用来更新TSS中的内核栈顶指针esp0, Linux任务切换的方式，只修改TSS的特权级0对应的栈。将TSS中的esp0修改为参数线程的0级栈，也就是线程PCB所在页的最顶端。此栈地址是用户进程由用户态进入内核态时所用的栈。

~~~c
// 头文件 tss.h

#ifndef __USERPROG_TSS_H
#define __USERPROG_TSS_H

#include "thread.h"
void update_tss_esp(struct task_struct* pthread);
void tss_init(void);

#endif


~~~

~~~c
// tss.c文件

#include "tss.h"
#include "stdint.h"
#include "global.h"
#include "string.h"
#include "print.h"

/* 任务状态段tss结构 */
struct tss {
    uint32_t backlink;
    uint32_t* esp0;
    uint32_t ss0;
    uint32_t* esp1;
    uint32_t ss1;
    uint32_t* esp2;
    uint32_t ss2;
    uint32_t cr3;
    uint32_t (*eip) (void);
    uint32_t eflags;
    uint32_t eax;
    uint32_t ecx;
    uint32_t edx;
    uint32_t ebx;
    uint32_t esp;
    uint32_t ebp;
    uint32_t esi;
    uint32_t edi;
    uint32_t es;
    uint32_t cs;
    uint32_t ss;
    uint32_t ds;
    uint32_t fs;
    uint32_t gs;
    uint32_t ldt;
    uint32_t trace;
    uint32_t io_base;
}; 
static struct tss tss;

/* 更新tss中esp0字段的值为pthread的0级线 */
void update_tss_esp(struct task_struct* pthread) {
   	tss.esp0 = (uint32_t*)((uint32_t)pthread + PG_SIZE);
}

/* 创建gdt描述符 */
static struct gdt_desc make_gdt_desc(uint32_t* desc_addr, uint32_t limit, uint8_t attr_low, uint8_t attr_high) {
   	uint32_t desc_base = (uint32_t)desc_addr;
   	struct gdt_desc desc;
   	desc.limit_low_word = limit & 0x0000ffff;
   	desc.base_low_word = desc_base & 0x0000ffff;
   	desc.base_mid_byte = ((desc_base & 0x00ff0000) >> 16);
   	desc.attr_low_byte = (uint8_t)(attr_low);
   	desc.limit_high_attr_high = (((limit & 0x000f0000) >> 16) + (uint8_t)(attr_high));
   	desc.base_high_byte = desc_base >> 24;
   	return desc;
}

/* 在gdt中创建tss并重新加载gdt */
void tss_init() {
   	put_str("tss_init start\n");
   	uint32_t tss_size = sizeof(tss);
   	memset(&tss, 0, tss_size);
   	tss.ss0 = SELECTOR_K_STACK;
   	tss.io_base = tss_size;
	// gdt段基址为0x900,把tss放到第4个位置,也就是0x900+0x20的位置
  	// 在gdt中添加dpl为0的TSS描述符 
  	*((struct gdt_desc*)0xc0000920) = make_gdt_desc((uint32_t*)&tss, tss_size - 1, TSS_ATTR_LOW, TSS_ATTR_HIGH);

  	// 在gdt中添加dpl为3的数据段和代码段描述符 
  	*((struct gdt_desc*)0xc0000928) = make_gdt_desc((uint32_t*)0, 0xfffff, GDT_CODE_ATTR_LOW_DPL3, GDT_ATTR_HIGH);
  	*((struct gdt_desc*)0xc0000930) = make_gdt_desc((uint32_t*)0, 0xfffff, GDT_DATA_ATTR_LOW_DPL3, GDT_ATTR_HIGH);
   
  	// gdt 16位的limit 32位的段基址 
   	uint64_t gdt_operand = ((8 * 7 - 1) | ((uint64_t)(uint32_t)0xc0000900 << 16));   
   	asm volatile ("lgdt %0" : : "m" (gdt_operand));
   	asm volatile ("ltr %w0" : : "r" (SELECTOR_TSS));
   	put_str("tss_init and ltr done\n");
}

~~~



