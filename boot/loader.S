%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
   
;构建gdt及其内部的描述符
GDT_BASE:   
    dd    0x00000000 
	dd    0x00000000

CODE_DESC:  
    dd    0x0000FFFF 
	dd    DESC_CODE_HIGH4

DATA_STACK_DESC:  
    dd    0x0000FFFF
	dd    DESC_DATA_HIGH4

VIDEO_DESC: 
    dd    0x80000007	        ; limit=(0xbffff-0xb8000)/4k=0x7
	dd    DESC_VIDEO_HIGH4      ; 此时dpl为0

GDT_SIZE    equ   $ - GDT_BASE
GDT_LIMIT   equ   GDT_SIZE - 1 

times 60 dq 0				    ; 此处预留60个描述符的空位(slot)

SELECTOR_CODE  equ (0x0001<<3) + TI_GDT + RPL0  ; 相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
SELECTOR_DATA  equ (0x0002<<3) + TI_GDT + RPL0	; 同上
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0	; 同上 

; total_mem_bytes用于保存内存容量,以字节为单位,此位置比较好记。
; 当前偏移loader.bin文件头(3 + 4 * 8 + 59 * 8 + 5) = 512 = 0x203字节), loader.bin的加载地址是0x900,
; 故total_mem_bytes内存中的地址是(0x900 + 0x200 = 0xb00).将来在内核中咱们会引用此地址
total_mem_bytes dd 0					 

;以下是定义gdt的指针，前2字节是gdt界限，后4字节是gdt起始地址
gdt_ptr     dw  GDT_LIMIT 
	        dd  GDT_BASE

;人工对齐:total_mem_bytes 4字节 + gdt_ptr 6字节 + ards_buf 244字节 + ards_nr 2字节,共256字节
ards_buf times 244 db 0
ards_nr dw 0		        ;用于记录ards结构体数量

;-------  int 15h eax = 0000E820h ,edx = 534D4150h ('SMAP') 获取内存布局  -------
loader_start:
    xor ebx, ebx		        ; 第一次调用时，ebx值要为0
    mov edx, 0x534d4150	        ; edx只赋值一次，循环体中不会改变
    mov di, ards_buf	        ; ards结构缓冲区

; 循环获取每个ARDS内存范围描述结构
.e820_mem_get_loop:	      
    mov eax, 0x0000e820	        ; 执行int 0x15后,eax值变为0x534d4150,所以每次执行int前都要更新为子功能号。
    mov ecx, 20		            ; ARDS地址范围描述符结构大小是20字节

    int 0x15
    jc .e820_failed_so_try_e801 ; 若cf位为1则有错误发生，尝试0xe801子功能
    add di, cx		            ; 使di增加20字节指向缓冲区中新的ARDS结构位置
    inc word [ards_nr]	        ;记录ARDS数量
    cmp ebx, 0		            ;若ebx为0且cf不为1,这说明ards全部返回，当前已是最后一个
    jnz .e820_mem_get_loop

; 在所有ards结构中，找出(base_add_low + length_low)的最大值，即内存的容量。
    mov cx, [ards_nr]	        ; 遍历每一个ARDS结构体,循环次数是ARDS的数量
    mov ebx, ards_buf 
    xor edx, edx		        ; edx为最大的内存容量, 在此先清0

; 无须判断type是否为1,最大的内存块一定是可被使用
.find_max_mem_area:	      
    mov eax, [ebx]	            ; base_add_low
    add eax, [ebx + 8]	        ; length_low
    add ebx, 20		            ; 指向缓冲区中下一个ARDS结构
    cmp edx, eax		        ; 冒泡排序，找出最大, edx寄存器始终是最大的内存容量
    jge .next_ards
    mov edx, eax		        ; edx为总内存大小
.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok

;------  int 15h ax = E801h 获取内存大小,最大支持4G  ------
; 返回后, ax cx 值一样,以KB为单位,bx dx值一样,以64KB为单位
; 在ax和cx寄存器中为低16M,在bx和dx寄存器中为16MB到4G。
.e820_failed_so_try_e801:
    mov ax, 0xe801
    int 0x15
    jc .e801_failed_so_try88    ;若当前e801方法失败,就尝试0x88方法

; 1 先算出低15M的内存,ax和cx中是以KB为单位的内存数量,将其转换为以byte为单位
    mov cx,0x400	            ; cx和ax值一样,cx用做乘数
    mul cx 
    shl edx, 16
    and eax, 0x0000FFFF
    or edx, eax
    add edx, 0x100000           ; ax只是15MB,故要加1MB
    mov esi, edx	            ; 先把低15MB的内存容量存入esi寄存器备份

; 2 再将16MB以上的内存转换为byte为单位,寄存器bx和dx中是以64KB为单位的内存数量
    xor eax, eax
    mov ax, bx		
    mov ecx, 0x10000	        ; 0x10000十进制为64KB
    mul ecx		                ; 32位乘法,默认的被乘数是eax,积为64位,高32位存入edx,低32位存入eax.
    add esi, eax		        ; 由于此方法只能测出4G以内的内存,故32位eax足够了,edx肯定为0,只加eax便可
    mov edx, esi		        ; edx为总内存大小
    jmp .mem_get_ok

;-----------------  int 15h ah = 0x88 获取内存大小,只能获取64M之内  ----------
.e801_failed_so_try88: 
    ;int 15后，ax存入的是以kb为单位的内存容量
    mov  ah, 0x88
    int  0x15
    jc .error_hlt
    and eax, 0x0000FFFF
      
    ;16位乘法，被乘数是ax,积为32位.积的高16位在dx中，积的低16位在ax中
    mov cx, 0x400     ; 0x400等于1024,将ax中的内存容量换为以byte为单位
    mul cx
    shl edx, 16	      ; 把dx移到高16位
    or edx, eax	      ; 把积的低16位组合到edx,为32位的积
    add edx,0x100000  ; 0x88子功能只会返回1MB以上的内存,故实际内存大小要加上1MB

; 将内存换为byte单位后存入total_mem_bytes处。
.mem_get_ok:
    mov [total_mem_bytes], edx	 


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

    jmp dword SELECTOR_CODE:p_mode_start	     ; 刷新流水线，避免分支预测的影响,这种cpu优化策略，最怕jmp跳转，

; 出错则挂起
.error_hlt:		      
    hlt

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

; ----------- 加载kernel ---------- 
    mov eax, KERNEL_START_SECTOR    ; kernel.bin所在的扇区号
    mov ebx, KERNEL_BIN_BASE_ADDR   ; 从磁盘读出后，写入到ebx指定的地址
    mov ecx, 200                    ; 读入的扇区数 

    call rd_disk_m_32 

; 创建页目录及页表并初始化页内存位图
    call setup_page

; 要将描述符表地址及偏移量写入内存gdt_ptr,一会用新地址重新加载
    sgdt [gdt_ptr]	                        ; 存储到原来gdt所有的位置, [gdt_ptr] = GDT_LIMIT = 0x0903001f

;将gdt描述符中显存段描述符中的段基址+0xc0000000
    mov ebx, [gdt_ptr + 2]                  ; gdt_ptr + 2字节 = GDT_BASE = 0x00000903
    or dword [ebx + 0x18 + 4], 0xc0000000   ; 显存段是第3个段描述符,每个描述符是8字节,故0x18。段描述符的高4字节的最高位是段基址的31~24位

;将gdt的基址加上0xc0000000使其成为内核所在的高地址
    add dword [gdt_ptr + 2], 0xc0000000     ; GDT_BASE = 0xc0000903
    add esp, 0xc0000000                     ; 将栈指针同样映射到内核地址

; 把页目录地址赋给cr3
    mov eax, PAGE_DIR_TABLE_POS            
    mov cr3, eax

; 打开cr0的pg位(第31位)
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

;在开启分页后,用gdt新的地址重新加载
    lgdt [gdt_ptr]                      ; 重新加载

    jmp SELECTOR_CODE:enter_kernel      ; 强制刷新流水线，更新gdt 

enter_kernel:
    call kernel_init 
    mov esp, 0xc009f000 
    jmp KERNEL_ENTRY_POINT              ; 用地址0x1500访问测试 

; ---------- 将kernel.bin中的segment拷贝到编译地址 ---------- 
kernel_init:
    xor eax, eax 
    xor ebx, ebx    ; ebx 记录程序头表地址
    xor ecx, ecx    ; cx  记录程序头表的PHE数量 
    xor edx, edx    ; dx  记录PHE大小，即e_phensize 
    mov dx, [KERNEL_BIN_BASE_ADDR + 42]    ; 偏移文件42字节处的属性是e_phentsize,表示PHE大小
    mov ebx, [KERNEL_BIN_BASE_ADDR + 28]   ; 偏移文件开始部分28字节的地方是e_phoff,表示PHT在文件内的偏移量
    add ebx, KERNEL_BIN_BASE_ADDR          ; 其实该值是0x34 = 52,
    mov cx, [KERNEL_BIN_BASE_ADDR + 44]    ; 偏移文件44字节处是e_phnum,表示PHE数量

.each_segment:
    cmp byte [ebx + 0], PT_NULL		      ; 若p_type等于 PT_NULL,说明此program header未使用。
    je .PTNULL

;为函数memcpy压入参数,参数是从右往左依然压入.函数原型类似于 memcpy(dst,src,size)
    push dword [ebx + 16]		   ; PHT中偏移16字节处是文件中段大小p_filesz,压入函数memcpy的第三个参数:size
    mov eax, [ebx + 4]			   ; PHT中偏移4字节处是p_offset，本段在文件内的起始偏移量
    add eax, KERNEL_BIN_BASE_ADDR ; 加上kernel.bin被加载到的物理地址, eax为该段的物理地址
    push eax				            ; 压入函数memcpy的第二个参数:src
    push dword [ebx + 8]			   ; 压入函数memcpy的第一个参数:dst,PHT中偏移4字节处是内存中段的起始虚地址p_vaddr，这就是目的地址
    call mem_cpy				      ; 调用mem_cpy完成段复制
    add esp, 12				         ; 清理栈中压入的三个参数

.PTNULL:
    add ebx, edx				      ; edx为PHE大小,即e_phentsize,在此ebx指向下一个PHE
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
    push ecx            ; rep 指令用到了ecx, ecx对于外层段循环还有用,故入栈 

    mov edi, [ebp + 8]  ; dst
    mov esi, [ebp + 12] ; src 
    mov ecx, [ebp + 16] ; size
    rep movsb           ; 逐字节拷贝, esi --> edi 

    pop ecx 
    pop ebp 
    ret

; -------------   创建页目录及页表   ---------------

setup_page:
;先把页目录占用的空间逐字节清0
    mov ecx, 4096
    mov esi, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0    ; PAGE_DIR_TABLE_POS = 0x100000
    inc esi
    loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde:				     
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x1000 			      ; 此时eax为第一个页表的位置及属性
    mov ebx, eax				      ; 此处为ebx赋值，是为.create_pte做准备，ebx为基址。

;   下面将页目录项0和0xc00都存为第一个页表的地址，
;   一个页表可表示4MB内存,这样0xc03fffff以下的地址和0x003fffff以下的地址都指向相同的页表，
;   这是为将地址映射为内核地址做准备
    or eax, PG_US_U | PG_RW_W | PG_P        ; 页目录项的属性RW和P位为1,US为1,表示用户属性,所有特权级别都可以访问.
    mov [PAGE_DIR_TABLE_POS + 0x0], eax     ; 第1个目录项,在页目录表中的第1个目录项写入第一个页表的位置(0x101000)及属性为7
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax   ; 一个页表项占用4字节,0xc00表示第768个页表占用的目录项,0xc00以上的目录项用于内核空间,
	; 也就是页表的0xc0000000~0xffffffff共计1G属于内核,0x0~0xbfffffff共计3G属于用户进程.
    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax    ; 使最后一个目录项指向页目录表自己的地址

;下面创建页表项(PTE)
    mov ecx, 256				        ; 1M低端内存 / 每页大小4k = 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P	; 属性为7, US=1, RW=1, P=1
.create_pte:				  
    mov [ebx + esi * 4], edx			; 此时的ebx已经在上面通过eax赋值为0x101000,也就是第一个页表的地址 
    add edx, 4096                       ; edx，物理页4KB
    inc esi
    loop .create_pte

    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000 		            ; 此时eax为第二个页表的位置
    or eax, PG_US_U | PG_RW_W | PG_P    ; 页目录项的属性US,RW和P位都为1
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254			            ; 范围为第769~1022的所有目录项数量
    mov esi, 769
;创建内核其它页表的PDE
.create_kernel_pde:
    mov [ebx + esi * 4], eax
    inc esi
    add eax, 0x1000
    loop .create_kernel_pde
    ret


; 读取硬盘n个扇区 
rd_disk_m_32:
    mov esi, eax
    mov di, cx 

; 1. 0x1f2端口 设置要读取的扇区数 
    mov dx, 0x1f2 
    mov al, cl 
    out dx, al 

    mov eax, esi

; 2. 将LBA地址存入0x1f3 ~ 0x1f6 
    ; LBA 7 ~ 0 写入 0x1f3 
    mov dx, 0x1f3 
    out dx, al
    ; LBA 15 ~ 8 写入 0x1f4
    mov cl, 8
    shr eax, cl 
    mov dx, 0x1f4
    out dx, al 
    ; LBA 23 ~ 16 写入 0x1f5 
    shr eax, cl 
    mov dx, 0x1f5 
    out dx, al 
    ; LBA 27 ~ 24 写入 0x1f6 
    shr eax, cl 
    and al, 0x0f 
    or al, 0xe0   ; 设置 27 ~ 24 位为 1110, 表示LBA 模式 
    mov dx, 0x1f6 
    out dx, al 

; 3. 向0x1f7 端口写入读命令， 0x20 
    mov dx, 0x1f7 
    mov al, 0x20 
    out dx, al 

; 4.检测硬盘状态 
.not_ready:
    nop
    in al, dx 
    and al, 0x88 
    cmp al, 0x08 
    jnz .not_ready 

; 5.从0x1f0读数据 
    mov ax, di 
    mov dx, 256 
    mul dx 
    mov cx, ax 
    mov dx, 0x1f0 
.go_on_read:
    in ax, dx 
    mov [ebx], ax 
    add ebx, 2 
    loop .go_on_read 
    ret

