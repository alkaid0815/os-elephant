#include "thread.h"
#include "stdint.h"
#include "string.h"
#include "print.h"
#include "global.h"
#include "memory.h"
#include "debug.h"
#include "interrupt.h"
#include "list.h"
#include "process.h"
#include "sync.h"

task_struct *main_thread;			// 主线程PCB
list thread_ready_list;				// 就绪队列
list thread_all_list;					// 所有任务队列
static list_elem *thread_tag;	// 用于保存队列中的线程结点
lock pid_lock;								// 分配 pid 锁

extern void switch_to(task_struct *cur, task_struct *next);

/* 获取当前线程PCB指针 */
task_struct *running_thread() {
	uint32_t esp;
	asm volatile("mov %%esp, %0" : "=g" (esp));
	/* pcb起始地址是4096的倍数 */
	return (task_struct*)(esp & 0xfffff000);
}


/* 由 kernel_thread去执行function(func_arg) */
static void kernel_thread(thread_func *function, void *func_arg) {
	/* 执行function前要开中断,避免后面的时钟中断被屏蔽,而无法调度其他线程 */
	intr_enable();
	function(func_arg);
}

/* 分配 pid */
static pid_t allocate_pid(void) {
	static pid_t next_pid = 0;
	lock_acquire(&pid_lock);
	++next_pid;
	lock_release(&pid_lock);
	return next_pid;
}

/* 初始化线程栈thread_stack,将待执行的函数和参数放到thread_stack中相应的位置 */
void thread_create(task_struct *pthread, thread_func function, void *func_arg) {
	/* 先预留中断使用栈的空间, 可见thread.h中定义的结构 */
	pthread->self_kstack -= sizeof(intr_stack);

	/* 再留出线程栈空间, 可见thread.h中定义 */
	pthread->self_kstack -= sizeof(thread_stack);

	thread_stack *kthread_stack = (thread_stack*)pthread->self_kstack;
	kthread_stack->eip = kernel_thread;
	kthread_stack->function = function;
	kthread_stack->func_arg = func_arg;
	kthread_stack->ebp = kthread_stack->ebx = kthread_stack->esi = kthread_stack->edi = 0;
}

/* 初始化线程基本信息 */
void init_thread(task_struct *pthread, char *name, int prio) {
	memset(pthread, 0, sizeof(*pthread));
	pthread->pid = allocate_pid();
	strcpy(pthread->name, name);

	if (pthread == main_thread) {
		/* 由于把main函数也封装成一个线程,并且它一直是运行的,故将其直接设为TASK_RUNNING */
		pthread->status = TASK_RUNNING;
	} else {
		pthread->status = TASK_READY;
	}

	/* self_kstack是线程自己在内核态下使用的栈顶地址 */
	pthread->self_kstack = (uint32_t*)((uint32_t)pthread + PG_SIZE);
	pthread->priority = prio;
	pthread->ticks = prio;
	pthread->elapsed_ticks = 0;
	pthread->pgdir = NULL;
	pthread->stack_magic = 0x19870916;				// 自定义的魔数
}

/* 创建一优先级为prio的线程,线程名为name,线程所执行的函数是function(func_arg) */

task_struct* thread_start(char *name, int prio, thread_func function, void *func_arg) {
	/* pcb都位于内核空间,包括用户进程的pcb也是在内核空间 */
	task_struct* thread = get_kernel_pages(1);

	init_thread(thread, name, prio);
	thread_create(thread, function, func_arg);

	/* 确保之前不在队列中 */
	ASSERT(!elem_find(&thread_ready_list, &thread->general_tag));
	/* 加入就绪线程队列 */
	list_append(&thread_ready_list, &thread->general_tag);

	/* 确保之前不在队列中 */
	ASSERT(!elem_find(&thread_all_list, &thread->all_list_tag));
	/* 加入全部线程队列 */
	list_append(&thread_all_list, &thread->all_list_tag);

	return thread;
}

/* 将kernel中的main函数完善为主线程 */
static void make_main_thread(void) {
	/* 因为main线程早已运行,咱们在loader.S中进入内核时的mov esp,0xc009f000,
		就是为其预留pcb的,因此pcb地址为0xc009e000,不需要通过 get_kernel_page另分配一页
	*/
	main_thread = running_thread();
	init_thread(main_thread, "main", 31);

	/* main函数是当前线程,当前线程不在thread_ready_list中,所以只将其加在thread_all_list中 */
	ASSERT(!elem_find(&thread_all_list, &main_thread->all_list_tag));
	list_append(&thread_all_list, &main_thread->all_list_tag);
}

/* 实现任务调度 */
void schedule() {
	ASSERT(intr_get_status() == INTR_OFF);
	task_struct* cur = running_thread();
	if (cur->status == TASK_RUNNING) {
		// 若此线程只是cpu时间片到了,将其加入到就绪队列尾
		ASSERT(!elem_find(&thread_ready_list, &cur->general_tag));
		list_append(&thread_ready_list, &cur->general_tag);

		cur->ticks = cur->priority; // 重新将当前线程的ticks再重置为其priority
		cur->status = TASK_READY;
	} else {
		/* 若此线程需要某事件发生后才能继续上cpu运行,不需要将其加入队列,因为当前线程不在就绪队列中 */
	}

	ASSERT(!list_empty(&thread_ready_list));
	thread_tag = NULL;				// thread_tag清空
	/* 将 thread_ready_list 队列中的第一个就绪线程弹出,准备将其调度上cpu */
	thread_tag = list_pop(&thread_ready_list);
	task_struct *next = elem2entry(task_struct, general_tag, thread_tag);
	next->status = TASK_RUNNING;

	/* 激活任务页表等 */
	process_activate(next);
	switch_to(cur, next);
}

/* 初始化线程环境 */
void thread_init(void) {
	put_str("thread_init start\n");
	list_init(&thread_ready_list);	
	list_init(&thread_all_list);
	lock_init(&pid_lock);
	/* 将当前main函数创建为线程 */
	make_main_thread();
	put_str("thread_init done\n");
}

void thread_block(task_status stat) {
	/* stat的取值为TASK_BLOCKED,TASK_WAITING,TASK_HANGING,也就是只有这三种状态才不会被调度 */
	ASSERT(((stat == TASK_BLOCKED)|| (stat == TASK_WAITING) || (stat == TASK_HANGING)));
	intr_status old_status = intr_disable();

	task_struct* cur_thread = running_thread();
	cur_thread->status = stat;			// 置其状态为stat
	schedule();											// 将当前线程换下处理器
	/* 待当前线程被解除阻塞后才继续运行下面的intr_set_status */
	intr_set_status(old_status);
}

/* 将线程 pthread 解除阻塞 */
void thread_unblock(task_struct *pthread) {
	intr_status old_status = intr_disable();
	ASSERT(((pthread->status == TASK_BLOCKED)|| (pthread->status == TASK_WAITING) || (pthread->status == TASK_HANGING)));
	if (pthread->status != TASK_READY) {
		ASSERT(!elem_find(&thread_ready_list, &pthread->general_tag));
		if (elem_find(&thread_ready_list, &pthread->general_tag)) {
			PANIC("thread_unblock: blocked thread in ready_list\n");
		}
		list_push(&thread_ready_list, &pthread->general_tag);		// 放到队列的最前面，使其尽快得到调度
		pthread->status = TASK_READY;
	}
	intr_set_status(old_status);
}