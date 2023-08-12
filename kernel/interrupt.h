#ifndef __KERNEL_INTERRUPT_H
#define __KERNEL_INTERRUPT_H

typedef void *intr_handler;
void idt_init(void);

/**
 * 定义中断的两种状态:
 * INTR_OFF值为0,表示关中断
 * INTR_ON值为1,表示开中断
*/
typedef enum {
	INTR_OFF,
	INTR_ON
} intr_status;

intr_status intr_get_status(void);
intr_status intr_set_status(intr_status);
intr_status intr_enable(void);
intr_status intr_disable(void);
#endif