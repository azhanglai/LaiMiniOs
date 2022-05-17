[TOC]

### 1、 获取物理内存容量

说明：

1. loader文件的虚拟起始地址为0x900
2. 在文件开头构建了GDT及内部的段描述符（空段，代码段，数据段，显存段）,每个段8个字节，共		4*8=32字节，0x900 + 32 = 0x920
3. 为total_mem_bytes变量地址好记，在其前面填充60*8=480个字节空位，0x920 + 480 = 0xb00
4. 定义GDT的指令gdt_ptr，大小为6字节，gdt_ptr的地址等于0xb00 + total_mem_bytes大小（4字节）= 0xb04
5. 为了loader_start地址好记: 0xb04 + gdt_ptr(6字节) + ards_buf大小（244字节）+ ards_nr大小（2字节） = 0xb04 + 6 + 244 + 2 = 0xc00, 就是MBR跳转过来的地址jmp 0xc00			

**1.1** 为了后期做好内存管理工作，先得知道自己物理内存大小，可以通过调用BIOS中断0x15来获取物理内存容量，BIOS中断的3个子功能号存放到寄存器eax或ax中。

1. eax=0xe820：遍历主机上全部内存
2. ax=0xe801：分别检测低15MB 和 16M~4GB的内存，最大支持4GB
3. ah=0x88：最多检测64MB内存，实际内存超过此容量也按照64MB返回

![img](https://s2.loli.net/2022/02/12/Ci1NyOLX4KvFSQI.png)



![img](https://s2.loli.net/2022/02/12/5TapqbN4tWkJI8Y.png)

**1.2** 利用BIOS中断0x15子功能获取内存。中断的调用步骤：

1. 填写好“调用前输入”中列出的寄存器
2. 执行中断调用 int 0x15
3. 在标志寄存器eflags的CF位为0的情况下，“放回后输出”中对应的寄存器便会有对应的结果

**1.3** 获取了最大的物理内存容量并存入变量total_mem_bytes中。0xb00是变量total_mem_bytes加载到内存中的地址

### 2、 从实模式进入保护模式

**2.1** 从实模式进入保护模式需要3个步骤：①打开A20 ②加载GDT ③将CR0的pe位置1

**2.2** 打开A20地址线

1. IBM在键盘控制器上的一些输出线来控制第21根地址线（A20）的有效性，故被称为A20Gate。
2. 如果A20Gate被打开，可以访问全地址。
3. 如果A20Gate被禁止，只能访问1M内存空间，采用8086/8088的地址回绕

~~~assembly
;-----------------  打开A20  ----------------
; 将端口0x92的第1位置成1就可以了
in al, 0x92
or al, 0000_0010B
out 0x92, al
~~~

**2.3** 加载GDT（全局描述符表，俗称段表）

1. 全局描述符表（GDT）是保护模式下内存段的登记表，这是不同于实模式的显著特征之一。
2. 在实模式下，cs:ip 表示 段基址：偏移地址；在保护模式下，cs存的是“选择子”，其实就是用来索引全局描述符表（段表）中的段描述符，把全局描述符表当成数组，选择子就是数组的下标。CPU自动从段描述符中取出段基址，加上段内偏移地址，便凑成“段基址：段内偏移地址”

![img](https://s2.loli.net/2022/02/12/SOstuEQCkRzi4vn.png)

![img](https://s2.loli.net/2022/02/12/oyIaQn5DbgzqhRJ.png)

3.一个段描述符只用来定义（描述）一个内存段。内存段是一片内存区域，访问内存就要提供段基址，故要有段基址属性。为了限制程序访问内存的范围，还要对段大小进行约束 ，所以要有段界限属性。代码段要占用一个段描述符、数据段和栈段等，多个内存段也要各自占用一个段描述符。段描述符是放在GDT，段描述符大小为8个字节。

4.GDTR是一个48位的寄存器，专门用来存储GDT的内存地址及大小。使用lgdt指令加载GDTR寄存器

![img](https://s2.loli.net/2022/02/12/voKbtPsckpuBGQH.png)

~~~assembly
;-----------------  加载GDT  ----------------
; gdt_ptr划分两个部分，前16位是GDT的界限值，后32位是GDT的起始位置
; GDT 表示范围为2的16次方=65536字节，每个描述符大小是8字节，故GDT可容纳描述符数量是65536/8=8192个
lgdt [gdt_ptr]
~~~

5.选择子的作用主要是确定段描述符，确定描述符的目的，一是为了特权级、界限等安全考虑，最主要的还是确定段的基地址。选择子的索引值部分是13位，即2的13次方是8192,故最多索引8192个段，和GDT最多定义8192个描述符是吻合的。前2位RPL是请求者的当前特权级，第3位是TI，用来指示选择子是在GDT中，还是LDT中。

![img](https://s2.loli.net/2022/02/12/eOWIhj6dvEzoLTB.png)

**2.4** 保护模式的开关，CR0寄存器的PE位

1. CR0寄存器的第0位，即PE位，此位用于启用保护模式，是保护模式的开关。打开此位CPU才真正进入保护模式

   ![img](https://s2.loli.net/2022/02/12/jxEUPdpY287IKJS.png)

~~~assembly
;-----------------  cr0第0位置1  ----------------
mov eax, cr0
or eax, 0x00000001
mov cr0, eax
~~~

**2.5**  无条件远跳转jmp指令进入保护模式

~~~assembly
; SELECTOR_CODE ： 内核代码段选择子，在前程序中为 1000b(0x8)
; p_mode_start:    段内偏移，保护模式的起始
jmp dword SELECTOR_CODE:p_mode_start
; 跳转后，CS寄存器指向 SELECTOR_CODE
~~~

### 3、 将内核（kernel）从磁盘加载到内存

**3.1** MBR写在了硬盘的第0扇区，第1扇区空着，第2扇区写入了loader加载器，loader加载器编译后的二进制文件约1300多字节，占用3个扇区大小，所以2 ~ 4扇区不能再用了，第5扇区之后可以自由使用。我选的是第9扇区，一是为了loader哪天需要扩展，得预留空间。使用dd命令往磁盘写入编译后内核的二进制文件

~~~shell
# count=200,一次写入200个扇区； seek=9,跨过前9个扇区（0~8），在第9扇区开始写入
dd if=kernel.bin of=/***.img bs=512 count=200 seek=9 conv=notrunc
~~~

**3.2** 加载内核只是把内核从硬盘拷贝到内存中，并不是运行内核代码，这项工作在开启分页前后都可以。本系统安排在分页开始之前加载。内核很小，只需要安置在内存的低端1MB中就够了。内核被加载到内存后，加载器还要通过分析其elf结构将其展开到新的位置，故内核在内存中有两份拷贝，一份是elf格式的原文件kernel.bin,另一份是加载器解析elf格式的kernel.bin后在内存中生成的内核映像（将程序中的各种段segment复制到内存后的程序体），这个映像才是真正的运行的内核。将原文件kernel.bin加载到地址较高的空间，因为文件经过loader加载器解析后就没有用啦。内核映像放置到较低的地址，将来会往高地址处扩展。0x7e00~0x9fbff这片内存最适合放置原文件kernel.bin,为了方便，取个整，选择0x70000 ~ 0x9fbff放置，有0x2fbff=190KB字节的空间，而内核大小不超过100KB。![img](https://s2.loli.net/2022/02/12/eHInfGDdourycMw.png)

### 4、 启用内存分页机制

**4.1** 内存为什么要分页？

1. 线性地址：段基址+段内偏移地址，线性地址是唯一的，只能属于某一个进程。在未开启分页功能时，线性地址就是物理地址，程序中引用的线性地址是连续的，所以物理地址也连续的。
2. 在内存分页机制之前，是内存分段机制，线性地址等于物理地址，线性地址是由编译器器编译出来的，在一段中是连续的，故物理地址也是连续的。所以内存的分配方式连续的一段内存块，进程的段比较大，故会产生很多内存碎片
3. 解决内存分段机制下的问题，需要解除线性地址与物理地址一一对应的关系，然后将它们的关系重新建立。通过某种映射关系，将线性地址映射到任意物理地址。这种映射关系是通过一张表来实现，这张表就是页表

**4.2** 一级页表

1. CPU在不打开分页机制时，段基址和段内偏移地址经过段部件处理后所输出的线性地址，是物理地址。打开了分页机制，段部件输出的线性地址，不等同于物理地址，称为虚拟地址。虚拟地址对应的物理地址需要在页表中查找
2. 分页机制的思想：通过映射，可以使连续的线性地址与任意物理内存地址相关联，逻辑上连续的线性地址其对应的物理地址可以不连续。![img](https://s2.loli.net/2022/02/12/D5h1cWO79rS3ykK.png)
3. 一级页表模型。线性地址的一页对应物理地址的一页，页大小4KB。![img](https://s2.loli.net/2022/02/13/JRDlK8xm7SZ95By.png)
4. 分页机制打开前要将页表地址加载到控制寄存器CR3中，页表中页表项的地址就是物理地址。线性地址（虚拟地址）转换成物理地址过程图。![img](https://s2.loli.net/2022/02/12/R9vj1SykQ7dunNc.png)

**4.3** 二级页表

1. 一级页表中最多可容纳1M个页表项，每个页表项4B，页表项全满的话，是1M*4B=4MB大小；一级页表项必须提前建好，因为操作系统要占用4GB虚拟地址空间的高1GB，用户进程要占用3GB。每个进程都有自己的页表，进程一多，页表占用的空间就很客观了。故不要一次性的将全部页表项(PTE)建好，需要时动态创建页表项。需要用到二级页表。
2. 无论是几级页表，标准页的大小都是4KB，4GB线性地址空间最多有1M标准页。一级页表将1M标准页放置一张表中，二级页表是将1M个标准页平均放置1K个页表中。每个页表包含1K个页表项，页表项4B，故页表大小为1K*4B=4KB，刚好一个标准页的大小。每个页表的物理地址在页目录表中以页目录项（PDE）的形式存储。一个页目录有1024个页目录项。![img](https://s2.loli.net/2022/02/13/5l1VhcsFnmxGYXi.png)
3. 同一级页表一样，访问任何页表内的数据都要通过物理地址。由于PDE和PTE都是4B大小，给出了PDE和PTE索引后， 还需要背后乘以4，再加上页表物理地址，这才是最终要访问的绝对物理地址。

![img](https://s2.loli.net/2022/02/13/dUqowOTMI7CKfYF.png)![img](https://s2.loli.net/2022/02/13/fM7uAS5BpNWY6eC.png)

**4.3** 启用分页机制，需要按顺序做3件事：①构建好页目录表及页表 ②将页目录表地址写入控制寄存器CR3 ③寄存器CR0的PG位置1

1. 构建好页目录表及页表。页目录表和页表都存在物理内存中，页目录表的位置，放在物理地址0x100000(1M)处。让页表紧挨着页目录表。页目录大小为（1K*4B=4KB），所以第一个页表的物理地址在0x101000(1M+4KB)处。![image-20220213112741400](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20220213112741400.png) 创建页目录项：页目录项第0项和第768项(内核第一个页表)都指向的页表地址为0x101000（第一个页表） 。操作系统占用4GB虚拟地址空间的高1G（虚拟地址为0xc0000000,高10位为0x300,即十进制的768）；虚拟地址0xc00000000 ~ 0xc03fffff(3GB ~ 3GB + 4M)之间的内存指向物理内存（0 ~ 4M）的物理地址。这样实现了操作系统高1G的虚拟地址对应到了低端1MB。

   将页目录项第0项（0x100000）加入到页目录表中最后一个页目录项（0x100ffc）中,目的是为了将来能够动态操作页表。

   创建页表：一个页表能容纳1024 * 4KB=4MB, 第1个页表地址（0x101000）,它用来分配物理地址范围0 ~ 0x3fffff(4M)直接的物理页。也是虚拟地址0x0 ~ 0x3fffff(4M) 和 虚拟地址0xc0000000(3G) ~ 0xc03fffff(3G + 4M)映射的物理页。目前只需要1M空间，所以为1MB空间的页表项分配物理页。每个物理页是4KB,只需要一个页表中的1M/4KB=256个页表项即可。 

   创建内核其它页表的PDE：在目录表中把内核空间的目录项（768 ~ 1022）写满，目前只写了768项，目的是为了将来的用户进程做准备，使所用用户进程共享内核空间。写入目录项就把页表的地址写进去了，但未分配对应物理页。

2. 将页目录表地址写入控制寄存器CR3。CR3用于存储页表物理地址，故CR3寄存器称为页目录基址寄存器（PDBR）![img](https://s2.loli.net/2022/02/13/FztUPqWRGOk8wZx.png)

~~~assembly
; PAGE_DIR_TABLE_POS : 页目录表地址
; 把页目录地址赋给cr3
mov eax, PAGE_DIR_TABLE_POS
mov cr3, eax
~~~

 3. 寄存器CR0的PG位置1

    ~~~assembly
    ; 打开cr0的pg位(第31位)
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    ~~~

**4.4** 用虚拟地址访问页表

1. 虚拟地址的优势：虚拟地址可以与任何一个物理地址对应。最后一个页目录项中，指向页目录表的物理地址，这是让虚拟地址与物理地址乱序映射的关键。
2. 虚拟地址与物理地址的映射

~~~assembly
# cr3: 0x00100000
# |---------------------------------------------------------|
# |     virtual address     | --> |    Physical address     |
# |-------------------------|-----|-------------------------|
# | 0x00000000 ~ 0x000fffff | --> | 0x00000000 ~ 0x000fffff |  
# | 0xc0000000 ~ 0xc00fffff | --> | 0x00000000 ~ 0x000fffff |
# | 0xffc00000 ~ 0xffc00fff | --> | 0x00101000 ~ 0x00101fff |
# | 0xfff00000 ~ 0xfff00fff | --> | 0x00101000 ~ 0x00101fff |
# | 0xfffff000 ~ 0xffffffff | --> | 0x00100000 ~ 0x00100fff |
# |---------------------------------------------------------|
# 每行映射说明
# 1. cr3寄存器保存的是页目录表的物理地址
# 2. 第1行地址映射，虚拟地址低端1M内存映射到物理内存低端1M，这是第0个页表的作用,为256个页表项分配的1M的物理页,第0个页目录项指向该页表
# 3. 第2行地址映射，虚拟地址（3G ~ 3G+1M）内存映射到物理内存低端1M(0 ~ 1M)，这是第0个页表的作用,为256个页表项分配的1M的物理页，第768个页目录项指向该页表
# 4. 第3行地址映射，虚拟地址（3G+660M ~ 3G+660M+4KB）内存映射到物理内存(1M+4KB ~ 1M+8KB)，这是因为最后一个页目录项中，指向页目录表的物理地址。虚拟高10位0x3ff找到页表的位置，此时的页表就是页目录表，在中间10位0x000找页表项，从该页表项获取物理地址，故第0个页表项就是页目录表的第0个页目录项，记录的就是第一个页表的物理地址0x101000(1M+4KB)
# 5. 第4行地址映射，虚拟地址（3G+663M ~ 3G+663M+4KB）内存映射到物理内存(1M+4KB ~ 1M+8KB)，这是因为最后一个页目录项中，指向页目录表的物理地址。虚拟高10位0x3ff找到页表的位置，此时的页表就是页目录表，在中间10位0x300(768)找页表项，从该页表项获取物理地址，第768个页目录项，记录的就是第一个页表的物理地址0x101000(1M+4KB)
# 6. 第5行地址映射，虚拟地址（3G+663M+1020KB ~ 3G+663M+1MB）内存映射到物理内存(1M ~ 1M+4KB)，这是因为最后一个页目录项中，指向页目录表的物理地址。虚拟高10位0x3ff找到页表的位置，此时的页表就是页目录表，在中间10位0x3ff(1023)找页表项，从该页表项获取物理地址，第1023个页目录项，记录的就是页目录表的物理地址0x100000(1M)
~~~

**4.5** 重新加载GDT

1. 分页机制开启后，段基址+段内偏移地址得到的线性地址不是物理地址了，而是虚拟地址，虚拟地址需要通过页部件输出物理地址。故之前加载到GDTR寄存器中的gdt地址需要重新加载。

~~~assembly
# 分页开启前GDT起始地址：[gdt_ptr + 2] = gdt_base = 0x900
# 分页开启后GDT起始地址：[gdt_ptr + 2] = gdt_base = 0x900 + 0xc0000000 = 0xc0000900
# 分页开启前显存段地址：VIDEO_DESC = 0x000b8000 
# 分页开启后显存段地址：VIDEO_DESC = 0x000b8000 + 0xc0000000 = 0xc00b8000
# 栈顶指针ESP = 0xc0000000
~~~



### 5、 将内存中kernel.bin中的segment拷贝到编译的地址

**5.1** 操作系统是程序，是软件，用户程序也是软件，用一个程序去调用另一程序最最简单的方法，就是用jmp或call指令。BIOS就是这样调用MBR的，我们的MBR也是这样调用loader的。BIOS调用MBR，MBR的地址是0x7c00, MBR调用loader,loader的地址是0x900,这两个地址是固定的，目前的方法很不灵活，调用方需要提前和被调用方约定调用地址。在原先的纯二进制可执行文件加上新的文件头，在文件头中写入程序入口地址，程序入口地址信息与程序绑定。这样的方法就灵活了。

**5.2** ELF格式的二进制文件![img](https://s2.loli.net/2022/02/13/LHvFQi3zyE5WtS9.png)

1. 程序中最重要的部分就是段（segment）和（section）节，它们是真正的程序体，程序中有很多段，如代码段和数据段等，同样也有很多节，段是由节来组成的，多个节经过链接后就被合并成一个段了。段和节的信息也是用header来描述的，程序头program header, 节头是section header。程序中段和节的大小和数量是不固定的，用程序头表（PHT）和节头表（SHT）来描述。![img](https://s2.loli.net/2022/02/13/jLOiVdzFb7IgAlZ.png)

![img](https://s2.loli.net/2022/02/13/gAWDYaLmOiyPuIK.png)

![img](https://s2.loli.net/2022/02/13/YyZgOWtM93Gimfr.png)

**5.3**  将内存内核文件中的段拷贝到编译地址

~~~assembly
# 1.在ELF找到e_phentsize(PHE，段的大小)，每次加上段大小，就能找到下一个段，便于遍历文件中所有段
# 2.在ELF找到e_phoff(PHT，段表在文件内的偏移量)，可以直接定位PHT
# 3.在ELF找到e_phnum(PHE的数量),知道了段的数量，就可以知道复制多少个段了
# 4. 内存拷贝函数：memcpy(dst, src, size)
# size: p_filesz,该段在文件中的大小
# src: KERNEL_BIN_BASE_ADDR(0x70000) + p_offset(该段在文件内的起始偏移字节)
# dst: p_vaddr,该段在内存中的起始虚拟地址
~~~

![img](https://s2.loli.net/2022/02/13/WmvgpG1eKUfOx5u.png)

**5.4**  jmp 跳转到  KERNEL_ENTRY_POINT（0xc0001500）

~~~shell
# 设置内核入口
LD -m elf_i386 -Ttext 0xc0001500 -e main -o kernel.bin $^（所有依赖文件）
# -Ttext： 指定起始虚拟地址
# -e:指定程序的起始地址(可以是数字形式的地址，也可以是符号名)
~~~

### 6、 loader.S代码实现

~~~assembly
;--------------------------------------
;boot.inc头文件
;--------------------------------------
LOADER_BASE_ADDR equ 0x900 
LOADER_STACK_TOP equ LOADER_BASE_ADDR
LOADER_START_SECTOR equ 0x2

KERNEL_BIN_BASE_ADDR equ 0x70000
KERNEL_START_SECTOR equ 0x9
KERNEL_ENTRY_POINT equ 0xc0001500

; 页表配置  
PAGE_DIR_TABLE_POS equ 0x100000

; gdt描述符属性  
DESC_G_4K   equ	  1_00000000000000000000000b   
DESC_D_32   equ	   1_0000000000000000000000b
DESC_L	    equ	    0_000000000000000000000b	
DESC_AVL    equ	     0_00000000000000000000b	
DESC_LIMIT_CODE2  equ 1111_0000000000000000b
DESC_LIMIT_DATA2  equ DESC_LIMIT_CODE2
DESC_LIMIT_VIDEO2  equ 0000_000000000000000b
DESC_P	    equ		  1_000000000000000b
DESC_DPL_0  equ		   00_0000000000000b
DESC_DPL_1  equ		   01_0000000000000b
DESC_DPL_2  equ		   10_0000000000000b
DESC_DPL_3  equ		   11_0000000000000b
DESC_S_CODE equ		     1_000000000000b
DESC_S_DATA equ	  DESC_S_CODE
DESC_S_sys  equ		     0_000000000000b
DESC_TYPE_CODE  equ	      1000_00000000b	;x=1,c=0,r=0,a=0 代码段是可执行的,非依从的,不可读的,已访问位a清0.  
DESC_TYPE_DATA  equ	      0010_00000000b	;x=0,e=0,w=1,a=0 数据段是不可执行的,向上扩展的,可写的,已访问位a清0.

DESC_CODE_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_CODE2 + DESC_P + DESC_DPL_0 + DESC_S_CODE + DESC_TYPE_CODE + 0x00
DESC_DATA_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_DATA2 + DESC_P + DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x00
DESC_VIDEO_HIGH4 equ (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_VIDEO2 + DESC_P + DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x0b

; 选择子属性  
RPL0  equ   00b
RPL1  equ   01b
RPL2  equ   10b
RPL3  equ   11b
TI_GDT	 equ   000b
TI_LDT	 equ   100b

; 页表相关属性  
PG_P  equ   1b
PG_RW_R	 equ  00b 
PG_RW_W	 equ  10b 
PG_US_S	 equ  000b 
PG_US_U	 equ  100b 
; program type 定义
PT_NULL equ 0
~~~

~~~assembly
;--------------------------------------
;loader.S文件
;--------------------------------------
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
;构建gdt及其内部的描述符
GDT_BASE: 	dd    0x00000000 
	       	dd    0x00000000
	       
CODE_DESC: 	dd    0x0000FFFF 
	       	dd    DESC_CODE_HIGH4

DATA_STACK_DESC: 	dd    0x0000FFFF
		     		dd    DESC_DATA_HIGH4

VIDEO_DESC: dd    0x80000007	       	; limit=(0xbffff-0xb8000)/4k=0x7
	       	dd    DESC_VIDEO_HIGH4  	; 此时dpl为0

GDT_SIZE   	equ   $ - GDT_BASE
GDT_LIMIT   equ   GDT_SIZE - 1

times 60 dq 0					 		; 此处预留60个描述符的空位(slot)
   
SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0         
SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0	 
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0	  

; total_mem_bytes用于保存内存容量,以字节为单位,此位置比较好记。
; 当前偏移loader.bin文件头0x200字节,loader.bin的加载地址是0x900,
; 故total_mem_bytes内存中的地址是0xb00.
total_mem_bytes dd 0					 

;以下是定义gdt的指针，前2字节是gdt界限，后4字节是gdt起始地址
gdt_ptr 	dw  GDT_LIMIT 
	    	dd  GDT_BASE

;人工对齐:total_mem_bytes4字节+gdt_ptr6字节+ards_buf244字节+ards_nr2,共256字节
ards_buf times 244 db 0
ards_nr dw 0		      	;用于记录ards结构体数量

loader_start:
;-------  int 15h eax = 0000E820h ,edx = 534D4150h ('SMAP') 获取内存布局  -------
	xor ebx, ebx		      	;第一次调用时，ebx值要为0
   	mov edx, 0x534d4150	      	;edx只赋值一次，循环体中不会改变
   	mov di, ards_buf	      	;ards结构缓冲区
.e820_mem_get_loop:	      		;循环获取每个ARDS内存范围描述结构
   	mov eax, 0x0000e820	      
   	mov ecx, 20		      		;ARDS地址范围描述符结构大小是20字节
   	int 0x15
   	jc .e820_failed_so_try_e801 ;若cf位为1则有错误发生，尝试0xe801子功能
   	add di, cx		     
   	inc word [ards_nr]	      	;记录ARDS数量
   	cmp ebx, 0		      		;若ebx为0且cf不为1,这说明ards全部返回，当前已是最后一个
   	jnz .e820_mem_get_loop

;在所有ards结构中，找出(base_add_low + length_low)的最大值，即内存的容量。
   	mov cx, [ards_nr]	      	;遍历每一个ARDS结构体,循环次数是ARDS的数量
   	mov ebx, ards_buf 
   	xor edx, edx		      	;edx为最大的内存容量,在此先清0
.find_max_mem_area:	      		;无须判断type是否为1,最大的内存块一定是可被使用
   	mov eax, [ebx]	      
   	add eax, [ebx+8]	      
   	add ebx, 20		      		;指向缓冲区中下一个ARDS结构
   	cmp edx, eax		      	;冒泡排序，找出最大,edx寄存器始终是最大的内存容量
   	jge .next_ards
   	mov edx, eax		      	;edx为总内存大小
.next_ards:
   	loop .find_max_mem_area
   	jmp .mem_get_ok

;------  int 15h ax = E801h 获取内存大小,最大支持4G  ------
; 返回后, ax cx 值一样,以KB为单位,bx dx值一样,以64KB为单位
; 在ax和cx寄存器中为低16M,在bx和dx寄存器中为16MB到4G。
.e820_failed_so_try_e801:
   	mov ax,0xe801
   	int 0x15
   	jc .e801_failed_so_try88   ;若当前e801方法失败,就尝试0x88方法

;1 先算出低15M的内存,ax和cx中是以KB为单位的内存数量,将其转换为以byte为单位
  	 mov cx, 0x400	     	;cx和ax值一样,cx用做乘数
   	mul cx 
   	shl edx, 16
   	and eax, 0x0000FFFF
   	or edx, eax
   	add edx, 0x100000 		;ax只是15MB,故要加1MB
   	mov esi, edx	     	;先把低15MB的内存容量存入esi寄存器备份

;2 再将16MB以上的内存转换为byte为单位,寄存器bx和dx中是以64KB为单位的内存数量
   	xor eax,eax
   	mov ax,bx		
   	mov ecx, 0x10000		;0x10000十进制为64KB
   	mul ecx		
   	add esi,eax		;由于此方法只能测出4G以内的内存,故32位eax足够了,edx肯定为0,只加eax便可
   	mov edx,esi		;edx为总内存大小
   	jmp .mem_get_ok

;-----------------  int 15h ah = 0x88 获取内存大小,只能获取64M之内  ----------
.e801_failed_so_try88: 
   	;int 15后，ax存入的是以kb为单位的内存容量
   	mov  ah, 0x88
   	int  0x15
   	jc .error_hlt
   	and eax,0x0000FFFF
      
  	;16位乘法，被乘数是ax,积为32位.积的高16位在dx中，积的低16位在ax中
   	mov cx, 0x400     	;0x400等于1024,将ax中的内存容量换为以byte为单位
  	mul cx
   	shl edx, 16	     	;把dx移到高16位
   	or edx, eax	     	;把积的低16位组合到edx,为32位的积
   	add edx,0x100000  	;0x88子功能只会返回1MB以上的内存,故实际内存大小要加上1MB

.mem_get_ok:
   mov [total_mem_bytes], edx	 ;将内存换为byte单位后存入total_mem_bytes处。


;-----------------   准备进入保护模式   -------------------
;1 打开A20
;2 加载gdt
;3 将cr0的pe位置1

;-----------------  打开A20  ----------------
	in al, 0x92
   	or al, 0000_0010B
   	out 0x92, al
   	
;-----------------  加载GDT  ----------------
   	lgdt [gdt_ptr]

;-----------------  cr0第0位置1  ----------------
   	mov eax, cr0
   	or eax, 0x00000001
   	mov cr0, eax

   	jmp dword SELECTOR_CODE:p_mode_start	    
					     。
.error_hlt:		      	;出错则挂起
   	hlt

[bits 32]
p_mode_start:
   	mov ax, SELECTOR_DATA
   	mov ds, ax
   	mov es, ax
   	mov ss, ax
   	mov esp,LOADER_STACK_TOP
   	mov ax, SELECTOR_VIDEO
   	mov gs, ax

; -------------------------   加载kernel  ----------------------
   	mov eax, KERNEL_START_SECTOR        	; kernel.bin所在的扇区号
   	mov ebx, KERNEL_BIN_BASE_ADDR       	; 从磁盘读出后，写入到ebx指定的地址
   	mov ecx, 200			       			; 读入的扇区数

   	call rd_disk_m_32

   	; 创建页目录及页表并初始化页内存位图
   	call setup_page

   	;要将描述符表地址及偏移量写入内存gdt_ptr,一会用新地址重新加载
  	sgdt [gdt_ptr]	      

   	;将gdt描述符中视频段描述符中的段基址+0xc0000000
   	mov ebx, [gdt_ptr + 2]  
   	or dword [ebx + 0x18 + 4], 0xc0000000      

   	;将gdt的基址加上0xc0000000使其成为内核所在的高地址
   	add dword [gdt_ptr + 2], 0xc0000000
   	add esp, 0xc0000000        			; 将栈指针同样映射到内核地址

   	; 把页目录地址赋给cr3
   	mov eax, PAGE_DIR_TABLE_POS
   	mov cr3, eax

   	; 打开cr0的pg位(第31位)
   	mov eax, cr0
   	or eax, 0x80000000
   	mov cr0, eax

   	;在开启分页后,用gdt新的地址重新加载
   	lgdt [gdt_ptr]            

   	jmp SELECTOR_CODE:enter_kernel	  ;强制刷新流水线,更新gdt
   	
enter_kernel:    
   	call kernel_init
   	mov esp, 0xc009f000
   	jmp KERNEL_ENTRY_POINT                 ; 用地址0x1500访问测试，结果ok

;-----------------   将kernel.bin中的segment拷贝到编译的地址   -----------
kernel_init:
   	xor eax, eax
   	xor ebx, ebx		;ebx记录程序头表地址
   	xor ecx, ecx		;cx记录程序头表中的program header数量
   	xor edx, edx		;dx 记录program header尺寸,即e_phentsize

   	mov dx, [KERNEL_BIN_BASE_ADDR + 42]  ; 偏移文件42字节处的属性是e_phentsize,表示program header大小
   	mov ebx, [KERNEL_BIN_BASE_ADDR + 28] ; 偏移文件开始部分28字节的地方是e_phoff,表示第1个program header在文件中的偏移量
   	add ebx, KERNEL_BIN_BASE_ADDR
   	mov cx, [KERNEL_BIN_BASE_ADDR + 44]  ; 偏移文件开始部分44字节的地方是e_phnum,表示有几个program header

.each_segment:
   	cmp byte [ebx + 0], PT_NULL		 	 ; 若p_type等于 PT_NULL,说明此program header未使用。
   	je .PTNULL

   ;为函数memcpy压入参数,参数是从右往左依然压入.函数原型类似于 memcpy(dst,src,size)
   	push dword [ebx + 16]		  ; program header中偏移16字节的地方是p_filesz,压入函数memcpy的第三个参数:size
   	mov eax, [ebx + 4]			  ; 距程序头偏移量为4字节的位置是p_offset
   	add eax, KERNEL_BIN_BASE_ADDR ; 加上kernel.bin被加载到的物理地址,eax为该段的物理地址
   	push eax				      ; 压入函数memcpy的第二个参数:源地址
   	push dword [ebx + 8]		  ; 压入函数memcpy的第一个参数:目的地址,偏移程序头8字节的位置是p_vaddr，这就是目的地址
   	call mem_cpy				  ; 调用mem_cpy完成段复制
   	add esp,12				      ; 清理栈中压入的三个参数
   	
.PTNULL:
   	add ebx, edx				  ; edx为program header大小,即e_phentsize,在此ebx指向下一个program header 
   	loop .each_segment
   	ret

;----------  逐字节拷贝 mem_cpy(dst,src,size) ------------
;输入:栈中三个参数(dst,src,size)
;输出:无
;---------------------------------------------------------
mem_cpy:		      
   	cld
   	push ebp
   	mov ebp, esp
   	push ecx		   		; rep指令用到了ecx，但ecx对于外层段的循环还有用，故先入栈备份
   	mov edi, [ebp + 8]	   	; dst
   	mov esi, [ebp + 12]	   	; src
   	mov ecx, [ebp + 16]	   	; size
   	rep movsb		   		; 逐字节拷贝

   	;恢复环境
   	pop ecx		
   	pop ebp
   	ret

;-------------   创建页目录及页表   ---------------
setup_page:
;先把页目录占用的空间逐字节清0
   	mov ecx, 4096
   	mov esi, 0
.clear_page_dir:
   	mov byte [PAGE_DIR_TABLE_POS + esi], 0
   	inc esi
   	loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde:				     	; 创建Page Directory Entry
   	mov eax, PAGE_DIR_TABLE_POS
   	add eax, 0x1000 			    ; 此时eax为第一个页表的位置及属性
   	mov ebx, eax				    ; 此处为ebx赋值，是为.create_pte做准备，ebx为基址。
	; 页目录项的属性RW和P位为1,US为1,表示用户属性,所有特权级别都可以访问.
   	or eax, PG_US_U | PG_RW_W | PG_P	     
   	; 第1个目录项,在页目录表中的第1个目录项写入第一个页表的位置(0x101000)及属性(3)
   	mov [PAGE_DIR_TABLE_POS + 0x0], eax       
   	; 一个页表项占用4字节,0xc00表示第768个页表占用的目录项,0xc00以上的目录项用于内核空间,
	; 也就是页表的0xc0000000~0xffffffff共计1G属于内核,0x0~0xbfffffff共计3G属于用户进程.
   	mov [PAGE_DIR_TABLE_POS + 0xc00], eax     
   	sub eax, 0x1000
   	mov [PAGE_DIR_TABLE_POS + 4092], eax; 使最后一个目录项指向页目录表自己的地址

;下面创建页表项(PTE)
   	mov ecx, 256				     	; 1M低端内存 / 每页大小4k = 256
   	mov esi, 0
   	mov edx, PG_US_U | PG_RW_W | PG_P	; 属性为7,US=1,RW=1,P=1
   
.create_pte:				     		; 创建Page Table Entry
   	mov [ebx+esi*4],edx			     	; 此时的ebx已经在上面通过eax赋值为0x101000,也就是第一个页表的地址 
   	add edx,4096
   	inc esi
   	loop .create_pte

;创建内核其它页表的PDE
   	mov eax, PAGE_DIR_TABLE_POS
   	add eax, 0x2000 		     		; 此时eax为第二个页表的位置
   	or eax, PG_US_U | PG_RW_W | PG_P  	; 页目录项的属性RW和P位为1,US为0
   	mov ebx, PAGE_DIR_TABLE_POS
   	mov ecx, 254			    		; 范围为第769~1022的所有目录项数量
   	mov esi, 769
.create_kernel_pde:
   	mov [ebx+esi*4], eax
   	inc esi
   	add eax, 0x1000
   	loop .create_kernel_pde
   	ret


rd_disk_m_32:	   
	mov esi,eax	   
    mov di,cx	
    mov dx,0x1f2
    mov al,cl
    out dx,al           
	mov eax,esi	

;将LBA地址存入0x1f3 ~ 0x1f6
	;LBA地址7~0位写入端口0x1f3
    mov dx,0x1f3                       
    out dx,al                          
    ;LBA地址15~8位写入端口0x1f4
    mov cl,8
    shr eax,cl
    mov dx,0x1f4
    out dx,al
	;LBA地址23~16位写入端口0x1f5
    shr eax,cl
    mov dx,0x1f5
    out dx,al
	shr eax,cl
    and al,0x0f	   ;lba第24~27位
    or al,0xe0	   ; 设置7～4位为1110,表示lba模式
    mov dx,0x1f6
    out dx,al

;向0x1f7端口写入读命令，0x20 
    mov dx,0x1f7
    mov al,0x20                        
    out dx,al

;检测硬盘状态
.not_ready:		   ;测试0x1f7端口(status寄存器)的的BSY位
    nop
    in al,dx
    and al,0x88	   		;第4位为1表示硬盘控制器已准备好数据传输,第7位为1表示硬盘忙
    cmp al,0x08
    jnz .not_ready	   	;若未准备好,继续等。

;从0x1f0端口读数据
    mov ax, di	   
    mov dx, 256	   
    mul dx
    mov cx, ax	   
    mov dx, 0x1f0
.go_on_read:
    in ax,dx		
    mov [ebx], ax
    add ebx, 2
    loop .go_on_read
    ret

~~~



