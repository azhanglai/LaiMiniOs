[TOC]

### 1、 实模式下1MB内存布局

![img](https://s2.loli.net/2022/02/10/FcmzAeVJWGBESkC.png)

**1.1** Intel8086有20条地址线，2的20次方=1MB，故其可以访问1MB的内存空间，地址范围按十六进制表示，是0x00000 ~ 0xFFFFF。

**1.2** 内存地址0 ~ 0x9FFFF的空间范围是640KB，这片地址对应DRAM(动态随机访问内存)，也就是插在主板上的内存条。

**1.3** 内存地址0xF0000 ~ 0xFFFFF的空间范围是64KB，这片地址是ROM(只读存储器)，存的是BIOS的代码。BIOS（基本输入输出系统）的主要工作是检测、初始化硬件。BIOS建立了中断向量表，可以通过"int 中断号"来实现相关的硬件调用。

### 2、 BIOS(基本输入输出系统)

**2.1** BIOS本身是一个程序，程序要执行，就要有个入口地址，BIOS的入口地址为0xFFFF0

**2.2** CPU访问内存是用段基址+偏移地址来实现的，在实模式下，段地址要乘16（地址左移4位）才能与偏移地址相加，得到的便是物理地址。cs段寄存器存的是段基址，ip指令寄存器存的是偏移地址。

**2.3** 在开机瞬间，CPU的cs:ip寄存器被强制初始化为0xF000:0xFFF0，得到的物理就是0xFFFF0,此地址就是BIOS的入口地址，开始执行BIOS程序。

**2.4** BIOS执行 jmp far f000:e05b, 跳转到物理地址0xfe05b，BIOS真正开始的地方，接下来检测内存、显卡等外设信息，检测通过后，并初始化硬件。在内存中0 ~ 0x3FF处建立数据结构，中断向量表IVT并填写中断服务例程。

**2.5** BIOS最后一项工作校验启动盘中位于0盘0道1扇区的内容。（CHS方式，柱面，磁头，扇区）

**2.6** BIOS跳转到0x7c00。是用直接绝对远跳转指令jmp 0:0x7c00实现的，段寄存器cs会被替换成0，ip指令寄存器为0x7c00。

### 3、 MBR(主引导记录)

**3.1** MBR存放在磁盘的第一个扇区0盘0道1扇区，一个扇区的大小为512字节，磁盘第一个扇区末尾的两个字节分别是魔数0x55和0xaa。

**3.2** 编写主引导记录MBR,由于BIOS程序执行完毕后，CS:IP 为0x0:0x7c00, 故MBR的起始编译地址为0x7c00。vstart=0x7c00;vstart的作用是为section内数据指定一个虚拟的起始地址

**3.3** 用cs段寄存器的值（0）去初始化其他段寄存器，将栈顶指针sp赋值为0x7c00，gs段寄存器赋值为0xb800, 0xb800 ~ 0xbfff内存物理地址用于文本模式显示适配器，范围32KB,每屏可以显示2000个字符，显示器上每个字符占2个字节大小，故每屏字符实际占用4000字节。32KB的显存可以容纳32KB/4000B = 8屏的数据

**3.4** 操作显卡打印输出文本。屏幕上每个字符（2个字节），低字节是字符的ASCII码，高字节是字符属性，高字节低4位是字符前景色，高4位是字符背景色。

![img](https://s2.loli.net/2022/02/12/vwotnAU9cf3HhxW.png)

**3.5** 硬盘控制器端口。端口分为两组，Command Block registers用于向硬盘驱动器写入命令字或从硬盘控制器获得硬盘状态，Control Block registers用于控制硬盘工作状态。

![img](https://s2.loli.net/2022/02/12/uqfpBN2PcCYeGbv.png)

**3.6** LBA（逻辑块地址），LBA28,用28位比特来描述一个扇区的地址。最大的寻址范围2的28次方=268435456个扇区，每个扇区512字节，最大支持128GB。LBA48和LBA28的表示方式一样，最大支持128PB。

3.7 LBA寄存器，由LBA_low，LBA_mid, LBA_high 三个8位宽度 + device寄存器低4位

**3.8** 硬盘操作方法：

1. 设置要读取的扇区数，选择0x1f2端口（sector count）,写入待操作的扇区数
2. 将LBA_low (7~0位)写入0x1f3端口，LBA_mid (15~8位)写入0x1f4端口，LBA_low (23~16位)写入0x1f5端口， LBA(27~24位) 写入0x1f6端口(device), 1110b，表示LBA模式
3. 向0x1f7（command）端口写入读命令（0x20）,读取0x1f7（status）端口，判断硬盘工作是否完成
4. 从0x1f0端口读数据，每次读入一个字（2个字节），1个扇区512字节，需要读256次。

**3.9** 由于MBR只能存在磁盘第一个扇区512字节，没法为内核准备好环境，更没法将内核成功加载到内存并运行。故我们需要实现一个加载器（loader）,来完成初始化环境及加载内核的任务。我们把加载器放到磁盘的第2扇区（LBA方式，MBR在第0扇区，loader在第2扇区，它们之间隔一个扇区）

**3.10** 目前"可用的内存区域"有两段，0x500 ~ 0x7BFF 和 0x7E00 ~ 9FBFF。根据个人偏好，我实现的loader的加载地址选为0x900

### 4、 MBR.S 代码实现

**4.1** MBR主要的目的就是将内核加载器loader从硬盘（第2扇区）加载到内存（0x900），并jmp跳转到0x900 + 0x300 = 0xC00这个内存地址去执行

**4.2** 通过dd命令把二进制文件往磁盘上写入

~~~shell
dd if=mbr.bin of=/***.img bs=512 count=1 seek=0 conv=notrunc
~~~

~~~assembly
;--------------------------------------
;boot.inc文件
LOADER_START_SECTOR equ 0x2
LOADER_BASE_ADDR equ 0x900

;--------------------------------------
;MBR.S文件
; 主引导程序
%include "boot.inc"
SECTION MBR vstart=0x7c00         
    mov ax, cs      
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov sp, 0x7c00
    mov ax, 0xb800   ;显存
    mov gs, ax

; 清屏
    mov     ax, 0600h
    mov     bx, 0700h
    mov     cx, 0                  
    mov     dx, 184fh		    

    int     10h                    

; 输出字符串
    mov byte [gs:0x00], 'Z'
    mov byte [gs:0x01], 0xA4 ; A 表示绿色背景闪烁，4表示前景色为红色
    mov byte [gs:0x02], 'h'
    mov byte [gs:0x03], 0xA4
    mov byte [gs:0x04], 'a'
    mov byte [gs:0x05], 0xA4	   
    mov byte [gs:0x06], 'n'
    mov byte [gs:0x07], 0xA4
    mov byte [gs:0x08], 'g'
    mov byte [gs:0x09], 0xA4
    mov byte [gs:0x0a], ' '
    mov byte [gs:0x0b], 0xA4
    mov byte [gs:0x0c], 'L'
    mov byte [gs:0x0d], 0xA4
    mov byte [gs:0x0e], 'a'
    mov byte [gs:0x0f], 0xA4
    mov byte [gs:0x10], 'i'
    mov byte [gs:0x11], 0xA4
 
    mov eax, LOADER_START_SECTOR 	; 起始扇区LBA地址 0x2
    mov bx, LOADER_BASE_ADDR        ; 写入的地址 0x900
    mov cx, 4			            ; 待读入的扇区数
    call rd_disk_m_16		      	; 读取程序的起始部分（一个扇区）
  
    jmp LOADER_BASE_ADDR + 0x300
   
; 读取硬盘n个扇区
rd_disk_m_16:	   
    mov esi, eax      ; eax = LBA扇区号，esi备份eax
    mov di, cx        ; cx = 读入的扇区数， di备份cx
; 读写硬盘:
; 1.设置要读取的扇区数
    mov dx, 0x1f2     ; 0x1f2端口：sector count
    mov al, cl
    out dx, al        ; 读取的扇区数
    mov eax, esi      ; 恢复eax

; 2.将LBA地址存入 0x1f3 ~ 0x1f6
    ; LBA地址 7 ~ 0 位写入 0x1f3 : LBA low
    mov dx, 0x1f3                       
    out dx, al                          

    ; LBA地址 15 ~ 8 位写入 0x1f4 : LBA mid
    mov cl, 8
    shr eax, cl  
    mov dx, 0x1f4
    out dx, al

    ; LBA地址 23 ~ 16 位写入 0x1f5 : LBA hight
    shr eax, cl
    mov dx, 0x1f5
    out dx, al

    shr eax, cl
    and al, 0x0f      ; LBA第 24 ~ 27 位
    or al, 0xe0	      ; 设置 7 ~ 4 位为1110，表示LBA模式
    mov dx, 0x1f6     ; 0x1f6 : Device
    out dx, al

; 3. 向0x1f7端口写入读命令， 0x20
    mov dx, 0x1f7
    mov al, 0x20                        
    out dx, al

; 4. 检测硬盘状态
.not_ready:
    ; 同一端口，写时表示写入命令字，读时表示读入硬盘状态
    nop
    in al, dx
    and al, 0x88      ; 第4位为1表示硬盘控制器已准备好数据传输
    cmp al, 0x08      ; 第7位为1表示硬盘忙
    jnz .not_ready    

; 5. 从0x1f0端口读数据
    mov ax, di        ; di为要读取的扇区数，一个扇区有512字节，每次读入1字
    mov dx, 256       ; 供需di * 512 / 2次， di * 256
    mul dx
    mov cx, ax	   
    mov dx, 0x1f0

.go_on_read:
    in ax, dx
    mov [bx], ax
    add bx, 2		  
    loop .go_on_read
    ret

    times 510-($-$$) db 0
    db 0x55, 0xaa

~~~



