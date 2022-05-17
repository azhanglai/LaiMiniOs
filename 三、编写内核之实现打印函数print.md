[TOC]

### 1、 显卡的端口控制

**1.1** 端口实际上就是IO接口电路上的寄存器，为了能访问到这些CPU外部的寄存器，计算机系统为这些寄存器统一编址，一个寄存器被赋予一个地址，这些地址不是内存地址，这些地址就是我们所说的端口号，用专门的IO指令in和out来读写这些寄存器。把每一个寄存器分组视为一个寄存器数组，提供一个寄存器用于指定数组的下标，再提供一个寄存器用于对索引所指向的数组元素（寄存器）进行输入输出操作。这样用两个寄存器就能够定位寄存器数组中的任何寄存器。Address Register作为数组的索引， Data Register作为寄存器数组中该索引对应的寄存器![img](https://s2.loli.net/2022/02/13/RUs4nEB1gYC3f5X.png)

**1.2** 内存地址0 ~ 0x9FFFF的空间范围是640KB，这片地址对应DRAM(动态随机访问内存)，也就是插在主板上的内存条。

**1.3** 内存地址0xF0000 ~ 0xFFFFF的空间范围是64KB，这片地址是ROM(只读存储器)，存的是BIOS的代码。BIOS（基本输入输出系统）的主要工作是检测、初始化硬件。BIOS建立了中断向量表，可以通过"int 中断号"来实现相关的硬件调用。

### 2、实现单个字符的打印put_char

**2.1** pushad 让8个通用寄存器入栈，备份寄存器；需要保证gs段寄存器为正确的显存段选择子

**2.2** 获取当前的光标坐标值，光标坐标值是下一个可打印字符的位置

~~~assembly
;先获得高8位
   mov dx, 0x03d4  ; 索引寄存器
   mov al, 0x0e	   ; 用于提供光标位置的高8位
   out dx, al
   mov dx, 0x03d5  ; 通过读写数据端口0x3d5来获得或设置光标位置 
   in al, dx	   ; 得到了光标位置的高8位
   mov ah, al
   ;再获取低8位
   mov dx, 0x03d4
   mov al, 0x0f
   out dx, al
   mov dx, 0x03d5 
   in al, dx
~~~

**2.3** 在函数栈中获取待打印的字符；因为在函数执行前，会把函数参数压入栈中

**2.4** 判断待打印的字符是否为控制字符，若是回车符、换行符、退格符3种控制字符之一，则进入相应的处理流程；否则，其余字符都被粗暴的认为是可见字符，进入输出流程处理。

**2.5** 判断屏幕字符数是否大于2000,大于2000字符，超出屏幕大小，则需要滚屏；滚屏原理是将屏幕的1~24行搬运到0~23行，再将第24行用空格填充。

**2.6** 字符打印完后，更新光标坐标值，使其指向下一个打印字符的位置。

**2.7** popad 恢复寄存器

### 3、实现字符串的打印put_str

**3.1** 通过循环调用put_char来完成字符串中全部字符的打印。

### 4、实现整数的打印put_int

**4.1** 将32位整型数字转换成字符后输出；函数转换实现的原理是按十六进制来处理32位数字，每4位二进制表示1位十六进制，将各十六进制数字转换成对应的字符，一个8个十六进制数字要处理。

**4.2** 如果是0~9之间的数字，用该数字加上字符‘0’的ASCII码48，如果是A~F之间的数字，用该数字减去10后加上字符‘A’的ASCII码65

### 5、print.S代码实现

~~~c
// 头文件print.h

#ifndef __LIB_KERNEL_PRINT_H
#define __LIB_KERNEL_PRINT_H

#include "stdint.h"
void put_char(uint8_t char_asci);
void put_str(char* message);
void put_int(uint32_t num);	 
void set_cursor(uint32_t cursor_pos);

#endif
~~~

~~~assembly
; print.S 文件

TI_GDT 	equ 	0
RPL0  	equ   	0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0

section .data
put_int_buffer    dq    0     ; 定义8字节缓冲区用于数字到字符的转换

[bits 32]
section .text
;--------------------------------------------
;put_str 通过put_char来打印以0字符结尾的字符串
;--------------------------------------------
;输入：栈中参数为打印的字符串
;输出：无
global put_str
put_str:
	push ebx
   	push ecx
   	xor ecx, ecx			; 准备用ecx存储参数,清空
   	mov ebx, [esp + 12]		; 从栈中得到待打印的字符串地址 
.goon:
   	mov cl, [ebx]
   	cmp cl, 0		      	; 如果处理到了字符串尾,跳到结束处返回
   	jz .str_over
   	push ecx		      	; 为put_char函数传递参数
   	call put_char
   	add esp, 4		      	; 回收参数所占的栈空间
   	inc ebx		      		; 使ebx指向下一个字符
   	jmp .goon
.str_over:
   	pop ecx
   	pop ebx
   	ret

;----------------------------------------
;put_char功能描述:把栈中的1个字符写入光标所在处
;----------------------------------------  
global put_char
put_char:
   	pushad	   ; 备份32位寄存器环境
   	; 需要保证gs中为正确的视频段选择子,为保险起见,每次打印时都为gs赋值
   	mov ax, SELECTOR_VIDEO	     
   	mov gs, ax
;获取当前光标位置
   	;先获得高8位
   	mov dx, 0x03d4  	;索引寄存器
   	mov al, 0x0e	   	;用于提供光标位置的高8位
   	out dx, al
   	mov dx, 0x03d5  	;通过读写数据端口0x3d5来获得或设置光标位置 
   	in al, dx	   		;得到了光标位置的高8位
   	mov ah, al
   	;再获取低8位
   	mov dx, 0x03d4
   	mov al, 0x0f
   	out dx, al
   	mov dx, 0x03d5 
   	in al, dx
   	;将光标存入bx
   	mov bx, ax	  
   	;下面这行是在栈中获取待打印的字符
   	mov ecx, [esp + 36]	      ;pushad压入4×8＝32字节,加上主调函数的返回地址4字节,故esp+36字节
   	cmp cl, 0xd				  ;CR是0x0d,LF是0x0a
   	jz .is_carriage_return
   	cmp cl, 0xa
   	jz .is_line_feed

   	cmp cl, 0x8				  ;BS(backspace)的asc码是8
   	jz .is_backspace
   	jmp .put_other	   

.is_backspace:		      
   	dec bx
   	shl bx,1
  	 mov byte [gs:bx], 0x20 	;将待删除的字节补为0或空格皆可
   	inc bx
   	mov byte [gs:bx], 0x07
   	shr bx,1
   	jmp .set_cursor

.put_other:
   	shl bx, 1				  	; 光标位置是用2字节表示,将光标值乘2,表示对应显存中的偏移字节
   	mov [gs:bx], cl			  	; ascii字符本身
   	inc bx
   	mov byte [gs:bx],0x07		; 字符属性
   	shr bx, 1				  	; 恢复老的光标值
   	inc bx				  		; 下一个光标值
   	cmp bx, 2000
    ; 若光标值小于2000,表示未写到显存的最后,则去设置新的光标值
    ; 若超出屏幕字符数大小(2000)则换行处理
   	jl .set_cursor			  				  
.is_line_feed:				  	; 是换行符LF(\n)
.is_carriage_return:			; 是回车符CR(\r)
; 如果是CR(\r),只要把光标移到行首就行了。
   	xor dx, dx				  	; dx是被除数的高16位,清0.
   	mov ax, bx				  	; ax是被除数的低16位.
   	mov si, 80				  	
   	div si				  
   	sub bx, dx				  	; 光标值减去除80的余数便是取整
	; 以上4行处理\r的代码

.is_carriage_return_end:        ; 回车符CR处理结束
   	add bx, 80
   	cmp bx, 2000
.is_line_feed_end:			  	; 若是LF(\n),将光标移+80便可。  
   	jl .set_cursor

;屏幕行范围是0~24,滚屏的原理是将屏幕的1~24行搬运到0~23行,再将第24行用空格填充
.roll_screen:				  	; 若超出屏幕大小，开始滚屏
   	cld 
    ; 一共有2000-80=1920个字符要搬运,共1920*2=3840字节.一次搬4字节,共3840/4=960次 
   	mov ecx, 960				  
   	mov esi, 0xb80a0			; 第1行行首
   	mov edi, 0xb8000			; 第0行行首
   	rep movsd				  

   	mov ebx, 3840			  	; 最后一行首字符的第一个字节偏移= 1920 * 2
   	mov ecx, 80				  	;一行是80字符(160字节),每次清理1字符(2字节),一行需要移动80次
.cls:
   	mov word [gs:ebx], 0x0720 	;0x0720是黑底白字的空格键
   	add ebx, 2
   	loop .cls 
   	mov bx,1920				  	;将光标值重置为1920,最后一行的首字符.

.set_cursor:   
;将光标设为bx值
; 1先设置高8位
   	mov dx, 0x03d4			  	;索引寄存器
   	mov al, 0x0e				;用于提供光标位置的高8位
   	out dx, al
   	mov dx, 0x03d5			  	;通过读写数据端口0x3d5来获得或设置光标位置 
   	mov al, bh
   	out dx, al

; 2再设置低8位
   	mov dx, 0x03d4
   	mov al, 0x0f
   	out dx, al
   	mov dx, 0x03d5 
   	mov al, bl
   	out dx, al
.put_char_done: 
   	popad
   	ret

;--------------------   将小端字节序的数字变成对应的ascii后，倒置   ---------------
;输入：栈中参数为待打印的数字
;输出：在屏幕上打印16进制数字,并不会打印前缀0x,如打印10进制15时，只会直接打印f，不会是0xf
;----------------------------------------------------------------------------
global put_int
put_int:
   	pushad
   	mov ebp, esp
   	mov eax, [ebp+4*9]		       	; call的返回地址占4字节+pushad的8个4字节
   	mov edx, eax
   	mov edi, 7           			; 指定在put_int_buffer中初始的偏移量
   	mov ecx, 8			       		; 32位数字中,16进制数字的位数是8个
   	mov ebx, put_int_buffer

;将32位数字按照16进制的形式从低位到高位逐个处理,共处理8个16进制数字
.16based_4bits:			       		; 每4位二进制是16进制数字的1位,遍历每一位16进制数字
   	and edx, 0x0000000F		      
   	cmp edx, 9			       		; 数字0～9和a~f需要分别处理成对应的字符
   	jg .is_A2F 
   	add edx, '0'			       	; ascii码是8位大小。add求和操作后,edx低8位有效。
   	jmp .store
.is_A2F:
   	sub edx, 10			       		; A~F 减去10 所得到的差,再加上字符A的ascii码
   	add edx, 'A'

;将每一位数字转换成对应的字符后,按照类似“大端”的顺序存储到缓冲区put_int_buffer
;高位字符放在低地址,低位字符要放在高地址,这样和大端字节序类似,只不过咱们这里是字符序.
.store:
; 此时dl中应该是数字对应的字符的ascii码
  	mov [ebx+edi], dl		       
   	dec edi
   	shr eax, 4
   	mov edx, eax 
   	loop .16based_4bits

;现在put_int_buffer中已全是字符,打印之前,
;把高位连续的字符去掉,比如把字符000123变成123
.ready_to_print:
   	inc edi			       
.skip_prefix_0:  
   	cmp edi,8			       ; 若已经比较第9个字符了，表示待打印的字符串为全0 
   	je .full0 
;找出连续的0字符, edi做为非0的最高位字符的偏移
.go_on_skip:   
   	mov cl, [put_int_buffer+edi]
   	inc edi
   	cmp cl, '0' 
   	je .skip_prefix_0		 	; 继续判断下一位字符是否为字符0(不是数字0)
   	;edi在上面的inc操作中指向了下一个字符,若当前字符不为'0',要恢复edi指向当前字符		       
   	dec edi			       
   	jmp .put_each_num

.full0:
   	mov cl,'0'			       	; 输入的数字为全0时，则只打印0
.put_each_num:
   	push ecx			       	; 此时cl中为可打印的字符
   	call put_char
   	add esp, 4
   	inc edi			       			; 使edi指向下一个字符
   	mov cl, [put_int_buffer+edi]	; 获取下一个字符到cl寄存器
   	cmp edi,8
   	jl .put_each_num
   	popad
   	ret

global set_cursor
set_cursor:
   	pushad
   	mov bx, [esp+36]
   	
   	mov dx, 0x03d4			; 索引寄存器
   	mov al, 0x0e	 		; 用于提供光标位置的高8位
   	out dx, al
   	mov dx, 0x03d5			; 通过读写数据端口0x3d5来获得或设置光标位置 
   	mov al, bh
   	out dx, al
   	
   	mov dx, 0x03d4
   	mov al, 0x0f
   	out dx, al
   	mov dx, 0x03d5 
   	mov al, bl
   	out dx, al
   	popad
   	ret
~~~
