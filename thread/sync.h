#ifndef __THREAD_SYNC_H
#define __THREAD_SYNC_H

#include "list.h"
#include "stdint.h"
#include "thread.h"

/* 信号量结构 */
typedef struct {
	uint8_t value;
	list waiters;
} semaphore;

/* 锁结构 */
typedef struct {
	task_struct *holder;				// 锁的持有者
	semaphore semaphore;				// 用二元信号量实现锁
	uint32_t holder_repeat_nr;	// 锁的持有者重复申请锁的次数
} lock;

void sema_init(semaphore* psema, uint8_t value); 
void sema_down(semaphore* psema);
void sema_up(semaphore* psema);
void lock_init(lock* plock);
void lock_acquire(lock* plock);
void lock_release(lock* plock);

#endif