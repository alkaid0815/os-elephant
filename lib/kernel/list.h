#ifndef __LIB_KERNEL_LIST_H
#define __LIB_KERNEL_LIST_H

#include "global.h"

#define offset(struct_type, member) (int)(&((struct_type*)0)->member)
#define elem2entry(struct_type, struct_member_name, elem_ptr) \
							(struct_type*)((int) elem_ptr - offset(struct_type, struct_member_name))

/********** 定义链表结点成员结构 **********
 * 结点中不需要数据成元，只要求前驱和后继结点指针 */
typedef struct list_elem {
	struct list_elem *prev;
	struct list_elem *next;
} list_elem;

typedef struct {
	list_elem head;
	list_elem tail;
} list;

/* 自定义函数类型function,用于在list_traversal中做回调函数 */
typedef bool (function)(list_elem *, int arg);

void list_init(list*);
void list_insert_before(list_elem *before, list_elem *elem);
void list_push(list *plist, list_elem *elem);
// void list_iterate(list *plist);
void list_append(list *plist, list_elem *elem);
void list_remove(list_elem *pelem);
list_elem *list_pop(list *plist);
bool list_empty(list *plist);
uint32_t list_len(list *plist);
list_elem *list_traversal(list *plist, function func, int arg);
bool elem_find(list *plist, list_elem *obj_elem);

#endif