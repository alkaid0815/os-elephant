#include "list.h"
#include "interrupt.h"

/* 初始化双向链表 list */
void list_init(list *list) {
	list->head.prev = NULL;
	list->head.next = &list->tail;
	list->tail.prev = &list->head;
	list->tail.next = NULL;
}

/* 把链表元素 elem 插入在元素 before 之前 */
void list_insert_before(list_elem *before, list_elem *elem) {
	intr_status old_status = intr_disable();

	elem->next = before;
	elem->prev = before->prev;
	elem->prev->next = elem;
	before->prev = elem;

	intr_set_status(old_status);
}

/* 添加元素到列表队首,类似栈push操作 */
void list_push(list *plist, list_elem *elem) {
	list_insert_before(plist->head.next, elem);			// 在队头插入elem
}

/* 追加元素到链表队尾,类似队列的先进先出操作 */
void list_append(list *plist, list_elem *elem) {
	list_insert_before(&plist->tail, elem);			// 在队尾的前面插入
}

/* 使元素pelem脱离链表 */
void list_remove(list_elem *pelem) {
	intr_status old_status = intr_disable();

	pelem->prev->next = pelem->next;
	pelem->next->prev = pelem->prev;

	intr_set_status(old_status);
}

/* 将链表第一个元素弹出并返回,类似栈的pop操作 */
list_elem *list_pop(list *plist) {
	list_elem* elem = plist->head.next;
	list_remove(elem);
	return elem;
}

/* 判断链表是否为空,空时返回true,否则返回false */
bool list_empty(list *plist) {
	return plist->head.next == &plist->tail;
}

/* 返回链表长度 */
uint32_t list_len(list *plist) {
	uint32_t len = 0;
	list_elem *elem = plist->head.next;
	while (elem != &plist->tail) {
		++len;
		elem = elem->next;
	}
	return len;
}

/**
 * 把列表plist中的每个元素elem和arg传给回调函数func,
 * arg给func用来判断elem是否符合条件.
 * 本函数的功能是遍历列表内所有元素,逐个判断是否有符合条件的元素.
 * 找到符合条件的元素返回元素指针,否则返回 NULL
*/
list_elem *list_traversal(list *plist, function func, int arg) {
	list_elem *elem = plist->head.next;
	while (elem != &plist->tail) {
		if (func(elem, arg)) return elem;
		elem = elem->next;
	}

	return NULL;
}

/* 从链表中查找元素obj_elem,成功时返回true,失败时返回false */
bool elem_find(list *plist, list_elem *obj_elem) {
	list_elem *elem = plist->head.next;
	while (elem != &plist->tail) {
		if (elem == obj_elem) return true;
		elem = elem->next;
	}

	return false;
}
