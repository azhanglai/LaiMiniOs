; 主引导程
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

    mov byte [gs:0x00], '1'
    mov byte [gs:0x01], 0xA4 ; A 表示绿色背景闪烁，4表示前景色为红色

    mov byte [gs:0x02], ' '
    mov byte [gs:0x03], 0xA4

    mov byte [gs:0x04], 'M'
    mov byte [gs:0x05], 0xA4	   

    mov byte [gs:0x06], 'B'
    mov byte [gs:0x07], 0xA4

    mov byte [gs:0x08], 'R'
    mov byte [gs:0x09], 0xA4
 
    mov eax, LOADER_START_SECTOR     ; 起始扇区LBA地址 0x2
    mov bx, LOADER_BASE_ADDR         ; 写入的地址 0x900
    mov cx, 4			            ; 待读入的扇区数
    call rd_disk_m_16		      ; 读取程序的起始部分（一个扇区）
  
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

