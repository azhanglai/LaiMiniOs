[bits 32] 
section .text 
global switch_to
switch_to:
    ; 下面3行push,是为了方便看清楚栈的内容
    ; push next
    ; push cur
    ; push eip

    push esi
    push edi
    push ebx
    push ebp 

    mov eax, [esp + 20]     ; [esp + 20] == cur的PCB 
    mov [eax], esp          ; PCB的self_kstack字段，保存0级栈顶指针esp

    mov eax, [esp + 24]     ; [esp + 24] == next的PCB 
    mov esp, [eax]          ; esp栈顶指针指向next的self_kstack, 恢复next的0级栈，0级栈保存PCB  

    pop ebp 
    pop ebx 
    pop edi 
    pop esi 

    ret

