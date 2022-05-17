[TOC]

### 1、fork的实现

**1.1** fork利用老进程克隆出一个新进程并使新进程执行，新进程之所以能够执行，本质上是它具备程序体，其中包括代码和数据等资源。故fork就是把某个进程的全部资源复制了一份，然后处理器的cs:ip指向新进程的指令部分。

**1.2** 实现fork分两步，先复制进程资源，然后再跳过去执行。

**1.3**  复制进程的步骤：

1. 进程的PCB，即task_struct
2.  程序体，即代码段和数据段等
3. 用户栈，编译器会把局部变量在栈中创建，函数调用也离不开栈
4. 内核栈，进入内核态时，一方面要用它保存上下文环境，另一方面和用户栈作用一样
5. 虚拟地址池，每个进程拥有独立的内存空间，其虚拟地址是用虚拟地址池来管理的
6. 页表，让进程拥有独立的内存空间

~~~c
extern void intr_exit(void);

/* 将父进程的pcb、虚拟地址位图拷贝给子进程 */
static int32_t copy_pcb_vaddrbitmap_stack0(struct task_struct *child_thread, struct task_struct *parent_thread) {
    // 1.复制pcb所在的整个页,里面包含进程pcb信息及特级0极的栈,
    // 里面包含了返回地址, 然后再单独修改个别部分 
    memcpy(child_thread, parent_thread, PG_SIZE);

    child_thread->pid = fork_pid();
    child_thread->elapsed_ticks = 0;
    child_thread->status = TASK_READY;
    child_thread->ticks = child_thread->priority;   // 为新进程把时间片充满
    child_thread->parent_pid = parent_thread->pid;
    child_thread->general_tag.prev = child_thread->general_tag.next = NULL;
    child_thread->all_list_tag.prev = child_thread->all_list_tag.next = NULL;
    block_desc_init(child_thread->u_block_desc);

    // 2.复制父进程的虚拟地址池的位图
    uint32_t bitmap_pg_cnt = DIV_ROUND_UP((0xc0000000 - USER_VADDR_START) / PG_SIZE / 8 , PG_SIZE);
    void *vaddr_btmp = get_kernel_pages(bitmap_pg_cnt);
    if (vaddr_btmp == NULL) return -1;
    // 此时child_thread->userprog_vaddr.vaddr_bitmap.bits还是指向父进程虚拟地址的位图地址
    // 下面将child_thread->userprog_vaddr.vaddr_bitmap.bits指向自己的位图vaddr_btmp 
    memcpy(vaddr_btmp, child_thread->userprog_vaddr.vaddr_bitmap.bits, bitmap_pg_cnt * PG_SIZE);
    child_thread->userprog_vaddr.vaddr_bitmap.bits = vaddr_btmp;
    return 0;
}

/* 复制子进程的进程体(代码和数据)及用户栈 */
static void copy_body_stack3(struct task_struct* child_thread, struct task_struct* parent_thread, void* buf_page) {
    uint8_t *vaddr_btmp = parent_thread->userprog_vaddr.vaddr_bitmap.bits;
    uint32_t btmp_bytes_len = parent_thread->userprog_vaddr.vaddr_bitmap.btmp_bytes_len;
    uint32_t vaddr_start = parent_thread->userprog_vaddr.vaddr_start;
    uint32_t idx_byte = 0;
    uint32_t idx_bit = 0;
    uint32_t prog_vaddr = 0;

    // 在父进程的用户空间中查找已有数据的页 
    while (idx_byte < btmp_bytes_len) {
        if (vaddr_btmp[idx_byte]) {
	        idx_bit = 0;
	        while (idx_bit < 8) {
	            if ((BITMAP_MASK << idx_bit) & vaddr_btmp[idx_byte]) {
	                prog_vaddr = (idx_byte * 8 + idx_bit) * PG_SIZE + vaddr_start;
	                // 下面的操作是将父进程用户空间中的数据通过内核空间做中转,
                    // 最终复制到子进程的用户空间 

	                // 1.将父进程在用户空间中的数据复制到内核缓冲区buf_page,
	                // 目的是下面切换到子进程的页表后,还能访问到父进程的数据
	                memcpy(buf_page, (void*)prog_vaddr, PG_SIZE);
	                // 2.将页表切换到子进程
                    // 目的是避免下面申请内存的函数将pte及pde安装在父进程的页表中
	                page_dir_activate(child_thread);
	                // 3 申请虚拟地址prog_vaddr
	                get_a_page_without_opvaddrbitmap(PF_USER, prog_vaddr);
	                // 4.从内核缓冲区中将父进程数据复制到子进程的用户空间 
	                memcpy((void*)prog_vaddr, buf_page, PG_SIZE);
	                // 5.恢复父进程页表 
	                page_dir_activate(parent_thread);
	            }
	            idx_bit++;
	        }
        }
        idx_byte++;
    }
}

/* 为子进程构建thread_stack和修改返回值 */
static int32_t build_child_stack(struct task_struct *child_thread) {
    // 1.使子进程pid返回值为0 
    // 获取子进程0级栈栈顶 
   struct intr_stack *intr_0_stack = (struct intr_stack*)((uint32_t)child_thread + PG_SIZE - sizeof(struct intr_stack));
    // 修改子进程的返回值为0 
    intr_0_stack->eax = 0;

    // 2.为switch_to 构建 struct thread_stack,将其构建在紧临intr_stack之下的空间
    uint32_t *ret_addr_in_thread_stack  = (uint32_t*)intr_0_stack - 1;

    /***   这三行不是必要的,只是为了梳理thread_stack中的关系 ***/
    uint32_t* esi_ptr_in_thread_stack = (uint32_t*)intr_0_stack - 2; 
    uint32_t* edi_ptr_in_thread_stack = (uint32_t*)intr_0_stack - 3; 
    uint32_t* ebx_ptr_in_thread_stack = (uint32_t*)intr_0_stack - 4; 
    /**********************************************************/

    // ebp在thread_stack中的地址便是当时的esp(0级栈的栈顶),
    // 即esp为"(uint32_t*)intr_0_stack - 5" 
    uint32_t* ebp_ptr_in_thread_stack = (uint32_t*)intr_0_stack - 5; 

    // switch_to的返回地址更新为intr_exit,直接从中断返回 
    *ret_addr_in_thread_stack = (uint32_t)intr_exit;

    // 下面这两行赋值只是为了使构建的thread_stack更加清晰,其实也不需要,
    // 因为在进入intr_exit后一系列的pop会把寄存器中的数据覆盖 
    *ebp_ptr_in_thread_stack = *ebx_ptr_in_thread_stack =\
    *edi_ptr_in_thread_stack = *esi_ptr_in_thread_stack = 0;

    // 把构建的thread_stack的栈顶做为switch_to恢复数据时的栈顶 
    child_thread->self_kstack = ebp_ptr_in_thread_stack;	    
    return 0;
}

/* 更新inode打开数 */
static void update_inode_open_cnts(struct task_struct* thread) {
    int32_t local_fd = 3, global_fd = 0;
    while (local_fd < MAX_FILES_OPEN_PER_PROC) {
        global_fd = thread->fd_table[local_fd];
        ASSERT(global_fd < MAX_FILE_OPEN);
        if (global_fd != -1) {
	        if (is_pipe(local_fd)) {
	            file_table[global_fd].fd_pos++;
	        } else {
	            file_table[global_fd].fd_inode->i_open_cnts++;
	        }
        }
        local_fd++;
    }
}

/* 拷贝父进程本身所占资源给子进程 */
static int32_t copy_process(struct task_struct *child_thread, struct task_struct *parent_thread) {
    // 内核缓冲区,作为父进程用户空间的数据复制到子进程用户空间的中转 
    void *buf_page = get_kernel_pages(1);
    if (buf_page == NULL) {
        return -1;
    }

    // 1.复制父进程的pcb、虚拟地址位图、内核栈到子进程 
    if (copy_pcb_vaddrbitmap_stack0(child_thread, parent_thread) == -1) {
        return -1;
    }

    // 2.为子进程创建页表,此页表仅包括内核空间 
    child_thread->pgdir = create_page_dir();
    if(child_thread->pgdir == NULL) {
        return -1;
    }

    // 3.复制父进程进程体及用户栈给子进程 
    copy_body_stack3(child_thread, parent_thread, buf_page);

    // 4.构建子进程thread_stack和修改返回值pid 
    build_child_stack(child_thread);

    // 5.更新文件inode的打开数
    update_inode_open_cnts(child_thread);

    mfree_page(PF_KERNEL, buf_page, 1);
    return 0;
}

/* fork子进程,内核线程不可直接调用 */
pid_t sys_fork(void) {
    struct task_struct *parent_thread = running_thread();
    // 为子进程创建pcb(task_struct结构)
    struct task_struct *child_thread = get_kernel_pages(1);    
    if (child_thread == NULL) {
        return -1;
    }
    ASSERT(INTR_OFF == intr_get_status() && parent_thread->pgdir != NULL);

    if (copy_process(child_thread, parent_thread) == -1) {
        return -1;
    }

    // 添加到就绪线程队列和所有线程队列,子进程由调试器安排运行
    ASSERT(!elem_find(&thread_ready_list, &child_thread->general_tag));
    list_append(&thread_ready_list, &child_thread->general_tag);
    ASSERT(!elem_find(&thread_all_list, &child_thread->all_list_tag));
    list_append(&thread_all_list, &child_thread->all_list_tag);
   
    return child_thread->pid;    // 父进程返回子进程的pid
}
~~~

### 2、实现exec

**2.1** exec会把一个可执行文件的绝对路径作为参数，把当前正在运行的用户进程的进程体（代码段、数据段、堆、栈）用该可执行文件的进程体替换，从而实现了新进程的执行。只是替换进程体，新进程的pid依然是老进程的pid

**2.2** 用户进程是用C语言编写的，编译为elf格式，因此要把用户程序从文件系统上加载到内存执行，必然涉及到elf格式的解析

~~~c
extern void intr_exit(void);
typedef uint32_t Elf32_Word, Elf32_Addr, Elf32_Off;
typedef uint16_t Elf32_Half;

/* 32位elf头 */
struct Elf32_Ehdr {
   unsigned char e_ident[16];
   Elf32_Half    e_type;
   Elf32_Half    e_machine;
   Elf32_Word    e_version;
   Elf32_Addr    e_entry;
   Elf32_Off     e_phoff;
   Elf32_Off     e_shoff;
   Elf32_Word    e_flags;
   Elf32_Half    e_ehsize;
   Elf32_Half    e_phentsize;
   Elf32_Half    e_phnum;
   Elf32_Half    e_shentsize;
   Elf32_Half    e_shnum;
   Elf32_Half    e_shstrndx;
};

/* 程序头表Program header.就是段描述头 */
struct Elf32_Phdr {
   Elf32_Word p_type;		 // 见下面的enum segment_type
   Elf32_Off  p_offset;
   Elf32_Addr p_vaddr;
   Elf32_Addr p_paddr;
   Elf32_Word p_filesz;
   Elf32_Word p_memsz;
   Elf32_Word p_flags;
   Elf32_Word p_align;
};

/* 段类型 */
enum segment_type {
   PT_NULL,            // 忽略
   PT_LOAD,            // 可加载程序段
   PT_DYNAMIC,         // 动态加载信息 
   PT_INTERP,          // 动态加载器名称
   PT_NOTE,            // 一些辅助信息
   PT_SHLIB,           // 保留
   PT_PHDR             // 程序头表
};

/* 将文件描述符fd指向的文件中,偏移为offset,大小为filesz的段加载到虚拟地址为vaddr的内存 */
static bool segment_load(int32_t fd, uint32_t offset, uint32_t filesz, uint32_t vaddr) {
   uint32_t vaddr_first_page = vaddr & 0xfffff000;    // vaddr地址所在的页框
   uint32_t size_in_first_page = PG_SIZE - (vaddr & 0x00000fff);     // 加载到内存后,文件在第一个页框中占用的字节大小
   uint32_t occupy_pages = 0;
   /* 若一个页框容不下该段 */
   if (filesz > size_in_first_page) {
      uint32_t left_size = filesz - size_in_first_page;
      occupy_pages = DIV_ROUND_UP(left_size, PG_SIZE) + 1;	     // 1是指vaddr_first_page
   } else {
      occupy_pages = 1;
   }

   /* 为进程分配内存 */
   uint32_t page_idx = 0;
   uint32_t vaddr_page = vaddr_first_page;
   while (page_idx < occupy_pages) {
      uint32_t* pde = pde_ptr(vaddr_page);
      uint32_t* pte = pte_ptr(vaddr_page);

      /* 如果pde不存在,或者pte不存在就分配内存.
       * pde的判断要在pte之前,否则pde若不存在会导致
       * 判断pte时缺页异常 */
      if (!(*pde & 0x00000001) || !(*pte & 0x00000001)) {
	 if (get_a_page(PF_USER, vaddr_page) == NULL) {
	    return false;
	 }
      } // 如果原进程的页表已经分配了,利用现有的物理页,直接覆盖进程体
      vaddr_page += PG_SIZE;
      page_idx++;
   }
   sys_lseek(fd, offset, SEEK_SET);
   sys_read(fd, (void*)vaddr, filesz);
   return true;
}

/* 从文件系统上加载用户程序pathname,成功则返回程序的起始地址,否则返回-1 */
static int32_t load(const char* pathname) {
   int32_t ret = -1;
   struct Elf32_Ehdr elf_header;
   struct Elf32_Phdr prog_header;
   memset(&elf_header, 0, sizeof(struct Elf32_Ehdr));

   int32_t fd = sys_open(pathname, O_RDONLY);
   if (fd == -1) {
      return -1;
   }

   if (sys_read(fd, &elf_header, sizeof(struct Elf32_Ehdr)) != sizeof(struct Elf32_Ehdr)) {
      ret = -1;
      goto done;
   }

   /* 校验elf头 */
   if (memcmp(elf_header.e_ident, "\177ELF\1\1\1", 7) \
      || elf_header.e_type != 2 \
      || elf_header.e_machine != 3 \
      || elf_header.e_version != 1 \
      || elf_header.e_phnum > 1024 \
      || elf_header.e_phentsize != sizeof(struct Elf32_Phdr)) {
      ret = -1;
      goto done;
   }

   Elf32_Off prog_header_offset = elf_header.e_phoff; 
   Elf32_Half prog_header_size = elf_header.e_phentsize;

   /* 遍历所有程序头 */
   uint32_t prog_idx = 0;
   while (prog_idx < elf_header.e_phnum) {
      memset(&prog_header, 0, prog_header_size);
      
      /* 将文件的指针定位到程序头 */
      sys_lseek(fd, prog_header_offset, SEEK_SET);

     /* 只获取程序头 */
      if (sys_read(fd, &prog_header, prog_header_size) != prog_header_size) {
	 ret = -1;
	 goto done;
      }

      /* 如果是可加载段就调用segment_load加载到内存 */
      if (PT_LOAD == prog_header.p_type) {
	 if (!segment_load(fd, prog_header.p_offset, prog_header.p_filesz, prog_header.p_vaddr)) {
	    ret = -1;
	    goto done;
	 }
      }

      /* 更新下一个程序头的偏移 */
      prog_header_offset += elf_header.e_phentsize;
      prog_idx++;
   }
   ret = elf_header.e_entry;
done:
   sys_close(fd);
   return ret;
}

/* 用path指向的程序替换当前进程 */
int32_t sys_execv(const char* path, const char* argv[]) {
   uint32_t argc = 0;
   while (argv[argc]) {
      argc++;
   }
   int32_t entry_point = load(path);     
   if (entry_point == -1) {	 // 若加载失败则返回-1
      return -1;
   }
   
   struct task_struct* cur = running_thread();
   /* 修改进程名 */
   memcpy(cur->name, path, TASK_NAME_LEN);

   /* 修改栈中参数 */
   struct intr_stack* intr_0_stack = (struct intr_stack*)((uint32_t)cur + PG_SIZE - sizeof(struct intr_stack));
   /* 参数传递给用户进程 */
   intr_0_stack->ebx = (int32_t)argv;
   intr_0_stack->ecx = argc;
   intr_0_stack->eip = (void*)entry_point;
   /* 使新用户进程的栈地址为最高用户空间地址 */
   intr_0_stack->esp = (void*)0xc0000000;

   /* exec不同于fork,为使新进程更快被执行,直接从中断返回 */
   asm volatile ("movl %0, %%esp; jmp intr_exit" : : "g" (intr_0_stack) : "memory");
   return 0;
}

~~~

### 3、实现pipe

~~~c
/* 判断文件描述符local_fd是否是管道 */
bool is_pipe(uint32_t local_fd) {
   uint32_t global_fd = fd_local2global(local_fd); 
   return file_table[global_fd].fd_flag == PIPE_FLAG;
}

/* 创建管道,成功返回0,失败返回-1 */
int32_t sys_pipe(int32_t pipefd[2]) {
   int32_t global_fd = get_free_slot_in_global();

   /* 申请一页内核内存做环形缓冲区 */
   file_table[global_fd].fd_inode = get_kernel_pages(1); 

   /* 初始化环形缓冲区 */
   ioqueue_init((struct ioqueue*)file_table[global_fd].fd_inode);
   if (file_table[global_fd].fd_inode == NULL) {
      return -1;
   }
  
   /* 将fd_flag复用为管道标志 */
   file_table[global_fd].fd_flag = PIPE_FLAG;

   /* 将fd_pos复用为管道打开数 */
   file_table[global_fd].fd_pos = 2;
   pipefd[0] = pcb_fd_install(global_fd);
   pipefd[1] = pcb_fd_install(global_fd);
   return 0;
}

/* 从管道中读数据 */
uint32_t pipe_read(int32_t fd, void* buf, uint32_t count) {
   char* buffer = buf;
   uint32_t bytes_read = 0;
   uint32_t global_fd = fd_local2global(fd);

   /* 获取管道的环形缓冲区 */
   struct ioqueue* ioq = (struct ioqueue*)file_table[global_fd].fd_inode;

   /* 选择较小的数据读取量,避免阻塞 */
   uint32_t ioq_len = ioq_length(ioq);
   uint32_t size = ioq_len > count ? count : ioq_len;
   while (bytes_read < size) {
      *buffer = ioq_getchar(ioq);
      bytes_read++;
      buffer++;
   }
   return bytes_read;
}

/* 往管道中写数据 */
uint32_t pipe_write(int32_t fd, const void* buf, uint32_t count) {
   uint32_t bytes_write = 0;
   uint32_t global_fd = fd_local2global(fd);
   struct ioqueue* ioq = (struct ioqueue*)file_table[global_fd].fd_inode;

   /* 选择较小的数据写入量,避免阻塞 */
   uint32_t ioq_left = bufsize - ioq_length(ioq);
   uint32_t size = ioq_left > count ? count : ioq_left;

   const char* buffer = buf;
   while (bytes_write < size) {
      ioq_putchar(ioq, *buffer);
      bytes_write++;
      buffer++;
   }
   return bytes_write;
}

/* 将文件描述符old_local_fd重定向为new_local_fd */
void sys_fd_redirect(uint32_t old_local_fd, uint32_t new_local_fd) {
   struct task_struct* cur = running_thread();
   /* 针对恢复标准描述符 */
   if (new_local_fd < 3) {
      cur->fd_table[old_local_fd] = new_local_fd;
   } else {
      uint32_t new_global_fd = cur->fd_table[new_local_fd];
      cur->fd_table[old_local_fd] = new_global_fd;
   }
}

~~~

### 4、实现shell

~~~c
#define MAX_ARG_NR 16	   // 加上命令名外,最多支持15个参数

/* 存储输入的命令 */
static char cmd_line[MAX_PATH_LEN] = {0};
char final_path[MAX_PATH_LEN] = {0};      // 用于洗路径时的缓冲

/* 用来记录当前目录,是当前目录的缓存,每次执行cd命令时会更新此内容 */
char cwd_cache[MAX_PATH_LEN] = {0};

/* 输出提示符 */
void print_prompt(void) {
    printf("[OS@zhanglai %s]$ ", cwd_cache);
}

/* 从键盘缓冲区中最多读入count个字节到buf。*/
static void readline(char *buf, int32_t count) {
    assert(buf != NULL && count > 0);
    char* pos = buf;
    // 在不出错情况下,直到找到回车符才返回
    while (read(stdin_no, pos, 1) != -1 && (pos - buf) < count) { 
        switch (*pos) {
            // 找到回车或换行符后认为键入的命令结束,直接返回 
	        case '\n':
	        case '\r':
	            *pos = 0;	    // 添加cmd_line的终止字符0
	            putchar('\n');
	            return;

	        case '\b':
	            if (cmd_line[0] != '\b') {		// 阻止删除非本次输入的信息
	                --pos;	                    // 退回到缓冲区cmd_line中上一个字符
	                putchar('\b');
	            }
	            break;

	        // ctrl+l 清屏 
	        case 'l' - 'a': 
	            // 1 先将当前的字符'l'-'a'置为0 
	            *pos = 0;
	            // 2 再将屏幕清空 
	            clear();
	            // 3 打印提示符 
	            print_prompt();
	            // 4 将之前键入的内容再次打印 
	            printf("%s", buf);
	            break;

	        // ctrl+u 清掉输入 
	        case 'u' - 'a':
	            while (buf != pos) {
	                putchar('\b');
	                *(pos--) = 0;
	            }
	            break;

	        // 非控制键则输出字符 
	        default:
	            putchar(*pos);
	            pos++;
        }
    }
    printf("readline: can`t find enter_key in the cmd_line, max num of char is 128\n");
}

/* 分析字符串cmd_str中以token为分隔符的单词,将各单词的指针存入argv数组 */
static int32_t cmd_parse(char* cmd_str, char** argv, char token) {
    assert(cmd_str != NULL);
    int32_t arg_idx = 0;
    while(arg_idx < MAX_ARG_NR) {
        argv[arg_idx] = NULL;
        arg_idx++;
    }
    char* next = cmd_str;
    int32_t argc = 0;
    // 外层循环处理整个命令行 
    while(*next) {
        // 去除命令字或参数之间的空格 
        while(*next == token) {
	        next++;
        }
        // 处理最后一个参数后接空格的情况,如"ls dir2 " 
        if (*next == 0) {
	        break; 
        }
        argv[argc] = next;

        // 内层循环处理命令行中的每个命令字及参数 
        while (*next && *next != token) {	  // 在字符串结束前找单词分隔符
	        next++;
        }

        // 如果未结束(是token字符),使tocken变成0 
        if (*next) {
            // 将token字符替换为字符串结束符0,做为一个单词的结束,并将字符指针next指向下一个字符
	        *next++ = 0;	
        }
   
        // 避免argv数组访问越界,参数过多则返回0 
        if (argc > MAX_ARG_NR) {
	        return -1;
        }
        argc++;
    }
    return argc;
}

/* 执行命令 */
static void cmd_execute(uint32_t argc, char** argv) {
    if (!strcmp("ls", argv[0])) {
        buildin_ls(argc, argv);
    } else if (!strcmp("cd", argv[0])) {
        if (buildin_cd(argc, argv) != NULL) {
	        memset(cwd_cache, 0, MAX_PATH_LEN);
	        strcpy(cwd_cache, final_path);
        }
    } else if (!strcmp("pwd", argv[0])) {
        buildin_pwd(argc, argv);
    } else if (!strcmp("ps", argv[0])) {
        buildin_ps(argc, argv);
    } else if (!strcmp("clear", argv[0])) {
        buildin_clear(argc, argv);
    } else if (!strcmp("mkdir", argv[0])){
        buildin_mkdir(argc, argv);
    } else if (!strcmp("rmdir", argv[0])){
        buildin_rmdir(argc, argv);
    } else if (!strcmp("rm", argv[0])) {
        buildin_rm(argc, argv);
    } else if (!strcmp("help", argv[0])) {
        buildin_help(argc, argv);
    } else {      // 如果是外部命令,需要从磁盘上加载
        int32_t pid = fork();
        if (pid) {	   // 父进程
	        int32_t status;
            // 此时子进程若没有执行exit,my_shell会被阻塞,不再响应键入的命令
	        int32_t child_pid = wait(&status);          
            // 按理说程序正确的话不会执行到这句,fork出的进程便是shell子进程
	        if (child_pid == -1) {     
	            panic("my_shell: no child\n");
	        }
	        printf("child_pid %d, it's status: %d\n", child_pid, status);
         } else {	   // 子进程
	        make_clear_abs_path(argv[0], final_path);
	        argv[0] = final_path;

	        // 先判断下文件是否存在 
	        struct stat file_stat;
	        memset(&file_stat, 0, sizeof(struct stat));
	        if (stat(argv[0], &file_stat) == -1) {
	            printf("my_shell: cannot access %s: No such file or directory\n", argv[0]);
	            exit(-1);
	        } else {
	            execv(argv[0], argv);
	        }
        }
    }
}

char* argv[MAX_ARG_NR] = {NULL};
int32_t argc = -1;

/* 简单的shell */
void my_shell(void) {
    cwd_cache[0] = '/';
    while (1) {
        print_prompt(); 
        memset(final_path, 0, MAX_PATH_LEN);
        memset(cmd_line, 0, MAX_PATH_LEN);

        readline(cmd_line, MAX_PATH_LEN);
        // 若只键入了一个回车
        if (cmd_line[0] == 0) {	 
	        continue;
        }

        // 针对管道的处理
        char *pipe_symbol = strchr(cmd_line, '|');
        if (pipe_symbol) {
            // 支持多重管道操作,如cmd1|cmd2|..|cmdn,
            // cmd1的标准输出和cmdn的标准输入需要单独处理 

            // 1 生成管道
	        int32_t fd[2] = {-1};	    // fd[0]用于输入,fd[1]用于输出
	        pipe(fd);
	        // 将标准输出重定向到fd[1],使后面的输出信息重定向到内核环形缓冲区 
	        fd_redirect(1,fd[1]);

            // 2 第一个命令 
	        char *each_cmd = cmd_line;
	        pipe_symbol = strchr(each_cmd, '|');
	        *pipe_symbol = 0;

	        // 执行第一个命令,命令的输出会写入环形缓冲区 
	        argc = -1;
	        argc = cmd_parse(each_cmd, argv, ' ');
	        cmd_execute(argc, argv);

	        // 跨过'|',处理下一个命令 
	        each_cmd = pipe_symbol + 1;

	        // 将标准输入重定向到fd[0],使之指向内核环形缓冲区
	        fd_redirect(0,fd[0]);

            // 3 中间的命令,命令的输入和输出都是指向环形缓冲区
	        while ((pipe_symbol = strchr(each_cmd, '|'))) { 
	            *pipe_symbol = 0;
	            argc = -1;
	            argc = cmd_parse(each_cmd, argv, ' ');
	            cmd_execute(argc, argv);
	            each_cmd = pipe_symbol + 1;
	        }

            // 4 处理管道中最后一个命令 
	        // 将标准输出恢复屏幕 
            fd_redirect(1,1);

	        // 执行最后一个命令 
	        argc = -1;
	        argc = cmd_parse(each_cmd, argv, ' ');
	        cmd_execute(argc, argv);

            //5  将标准输入恢复为键盘 
            fd_redirect(0,0);

            // 6 关闭管道 
	        close(fd[0]);
	        close(fd[1]);
        } else {		// 一般无管道操作的命令
	        argc = -1;
	        argc = cmd_parse(cmd_line, argv, ' ');
	        if (argc == -1) {
	            printf("num of arguments exceed %d\n", MAX_ARG_NR);
	            continue;
	        }
	        cmd_execute(argc, argv);
        }
    }
    panic("my_shell: should not be here");
}

~~~

