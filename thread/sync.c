#include "sync.h"
#include "list.h"
#include "global.h"
#include "stdint.h"
#include "thread.h"
#include "interrupt.h"
#include "debug.h"

/* 初始化信号量 */
void sema_init(semaphore *psema, uint8_t value) {
	psema->value = value;
	list_init(&psema->waiters);
}

/* 初始化锁plock */
void lock_init(lock *plock) {
	plock->holder = NULL;
	plock->holder_repeat_nr = 0;
	sema_init(&plock->semaphore, 1);		// 信号量初值为1
}

/* 信号量down操作 */
void sema_down(semaphore *psema) {
	/* 关中断来保证原子操作 */
	intr_status old_status = intr_disable();
	while (psema->value == 0) {		// 若value为0,表示已经被别人持有
		ASSERT(!elem_find(&psema->waiters, &running_thread()->general_tag));
		/* 当前线程不应该已在信号量的waiters队列中 */
		if (elem_find(&psema->waiters, &running_thread()->general_tag)) {
			PANIC("sema_down: thread blocked has been in waiters_list\n");
		}

		/* 若信号量的值等于0,则当前线程把自己加入该锁的等待队列,然后阻塞自己 */
		list_append(&psema->waiters, &running_thread()->general_tag);
		thread_block(TASK_BLOCKED);
	}

	/* 若value大于0或被唤醒后,会执行下面的代码,也就是获得了锁 */
	--psema->value;
	intr_set_status(old_status);
}

/* 信号量up操作 */
void sema_up(semaphore *psema) {
	/* 关中断来保证原子操作 */
	intr_status old_status = intr_disable();
	if (psema->value == 0 && !list_empty(&psema->waiters)) {
		task_struct *thread_blocked = elem2entry(task_struct, general_tag, list_pop(&psema->waiters));
		thread_unblock(thread_blocked);
	}
	++psema->value;
	intr_set_status(old_status);
}

/* 获取锁plock */
void lock_acquire(lock *plock) {
	if (plock->holder != running_thread()) {
		sema_down(&plock->semaphore);			// 对信号量P操作，原子操作
		plock->holder = running_thread();
		ASSERT(plock->holder_repeat_nr == 0);
		plock->holder_repeat_nr = 1;
	} else {
		++plock->holder_repeat_nr;
	}
}

/* 释放锁 plock */
void lock_release(lock *plock) {
	ASSERT(plock->holder == running_thread());
	if (plock->holder_repeat_nr > 1) {
		--plock->holder_repeat_nr;
		return;
	}

	ASSERT(plock->holder_repeat_nr == 1);
	plock->holder = NULL;								// 把锁的持有者置空放在 V 操作之前
	plock->holder_repeat_nr = 0;
	sema_up(&plock->semaphore);					// 信号量的V操作，也是原子操作
}