[TOC]

### 1、 实现双向链表

**1.1** 算法再怎么简单，数据结构还是必不可少的，数据需要存储到合适的数据结构中才能获得更高效的管理。

**1.2** 内核中要用到队列，比如进程的就绪队列，锁的等待队列等，为了维护内核中的各种队列，要实现一个双向链表

### 2、 list.c代码实现

~~~c
// 头文件list.h

#ifndef __LIB_KERNEL_LIST_H
#define __LIB_KERNEL_LIST_H
#include "global.h"

#define offset(struct_type,member) (int)(&((struct_type*)0)->member)
#define elem2entry(struct_type, struct_member_name, elem_ptr) \
	 (struct_type*)((int)elem_ptr - offset(struct_type, struct_member_name))

/* 定义链表结点成员结构 */
struct list_elem {
   	struct list_elem* prev; 	// 前躯结点
   	struct list_elem* next; 	// 后继结点
};

/* 链表结构,用来实现队列 */
struct list {
   	struct list_elem head;
   	struct list_elem tail;
};

/* 自定义函数类型function,用于在list_traversal中做回调函数 */
typedef bool (function)(struct list_elem*, int arg);

void list_init (struct list*);
void list_insert_before(struct list_elem* before, struct list_elem* elem);
void list_push(struct list* plist, struct list_elem* elem);
void list_iterate(struct list* plist);
void list_append(struct list* plist, struct list_elem* elem);  
void list_remove(struct list_elem* pelem);
struct list_elem* list_pop(struct list* plist);
bool list_empty(struct list* plist);
uint32_t list_len(struct list* plist);
struct list_elem* list_traversal(struct list* plist, function func, int arg);
bool elem_find(struct list* plist, struct list_elem* obj_elem);
#endif

~~~

~~~c
// list.c 文件

#include "list.h"
#include "interrupt.h"

/* 初始化双向链表list */
void list_init (struct list* list) {
   	list->head.prev = NULL;
   	list->head.next = &list->tail;
   	list->tail.prev = &list->head;
   	list->tail.next = NULL;
}

/* 把链表元素elem插入在元素before之前 */
void list_insert_before(struct list_elem* before, struct list_elem* elem) { 
   	enum intr_status old_status = intr_disable();

   	before->prev->next = elem; 
   	elem->prev = before->prev;
   	elem->next = before;
   	before->prev = elem;

   intr_set_status(old_status);
}

/* 添加元素到列表队首,类似栈push操作 */
void list_push(struct list* plist, struct list_elem* elem) {
   	list_insert_before(plist->head.next, elem); 
}

/* 追加元素到链表队尾,类似队列的先进先出操作 */
void list_append(struct list* plist, struct list_elem* elem) {
   	list_insert_before(&plist->tail, elem);    
}

/* 使元素pelem脱离链表 */
void list_remove(struct list_elem* pelem) {
   	enum intr_status old_status = intr_disable();
   
   	pelem->prev->next = pelem->next;
   	pelem->next->prev = pelem->prev;

   intr_set_status(old_status);
}

/* 将链表第一个元素弹出并返回,类似栈的pop操作 */
struct list_elem* list_pop(struct list* plist) {
   	struct list_elem* elem = plist->head.next;
   	list_remove(elem);
   	return elem;
} 

/* 从链表中查找元素obj_elem,成功时返回true,失败时返回false */
bool elem_find(struct list* plist, struct list_elem* obj_elem) {
   	struct list_elem* elem = plist->head.next;
   	while (elem != &plist->tail) {
      	if (elem == obj_elem) {
	 		return true;
      	}
      	elem = elem->next;
   	}
   	return false;
}

/* 把列表plist中的每个元素elem和arg传给回调函数func,
 * arg给func用来判断elem是否符合条件.
 * 本函数的功能是遍历列表内所有元素,逐个判断是否有符合条件的元素。
 * 找到符合条件的元素返回元素指针,否则返回NULL. */
struct list_elem* list_traversal(struct list* plist, function func, int arg) {
   	struct list_elem* elem = plist->head.next;
   	if (list_empty(plist)) { 
      	return NULL;
   	}

   	while (elem != &plist->tail) {
        // func返回ture则认为该元素在回调函数中符合条件,命中,故停止继续遍历
      	if (func(elem, arg)) {		  
	 		return elem;
      	}
      	elem = elem->next;	       
   	}
   	return NULL;
}

/* 返回链表长度 */
uint32_t list_len(struct list* plist) {
   	struct list_elem* elem = plist->head.next;
   	uint32_t length = 0;
   	while (elem != &plist->tail) {
      	length++; 
      	elem = elem->next;
   	}
   	return length;
}

/* 判断链表是否为空,空时返回true,否则返回false */
bool list_empty(struct list* plist) {	
   	return (plist->head.next == &plist->tail ? true : false);
}


~~~

