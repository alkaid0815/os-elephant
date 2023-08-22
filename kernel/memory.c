#include "memory.h"
#include "bitmap.h"
#include "stdint.h"
#include "global.h"
#include "debug.h"
#include "print.h"
#include "string.h"
#include "sync.h"

#define PDE_INDEX(addr) ((addr & 0xffc00000) >> 22)
#define PTE_INDEX(addr) ((addr & 0x003ff000) >> 12)

// #define PG_SIZE 4096

/**************************** 位图地址 *****************************
 * 因为0xc009f000是内核主线程栈顶, 0xc009e000是内核主线程的pcb
 * 一个4K(0x1000)页框大小的位图可表示128MB(4096*8*4K)内存,位图位置安排
 * 在地址0xc009a000,这样本系统最大支持4个4K页框的位图,即512MB
*/
#define MEM_BITMAP_BASE 0xc009a000
/******************************************************************/

/**
 * 0xc0000000是内核从虚拟地址3G起
 * 0x100000意指跨过低端1MB内存,使虚拟地址在逻辑上连续
*/
#define K_HEAP_START 0xc0100000

/* 内存池结构，生成两个实例用于管理内核内存池和用户内存池 */
typedef struct
{
	bitmap pool_bitmap; 				// 本内存池用到的位图结构，用于管理物理内存
	uint32_t phy_addr_start; 		// 本内存池所管理物理内存的起始地址
	uint32_t pool_size; 				// 本内存池字节容量
	lock lock;									// 申请内存时互斥
} pool;

pool kernel_pool, user_pool;	// 生成内核内存池和用户内存池
virtual_addr kernel_vaddr; 		// 此结构用来给内核分配虚拟地址

/* 在pf表示的虚拟内存池中申请pg_cnt个虚拟页,成功则返回虚拟页的起始地址,失败则返回NULL */
static void *vaddr_get(pool_flags pf, uint32_t pg_cnt) {
	int vaddr_start = 0, bit_idx_start = -1;
	uint32_t cnt = 0;
	if (pf == PF_KERNEL) {
		bit_idx_start = bitmap_scan(&kernel_vaddr.vaddr_bitmap, pg_cnt);
		if (bit_idx_start == -1) return NULL;
		while (cnt < pg_cnt) {
			bitmap_set(&kernel_vaddr.vaddr_bitmap, bit_idx_start + cnt++, 1);
		}
		vaddr_start = kernel_vaddr.vaddr_start + bit_idx_start * PG_SIZE;
	} else { 			// 用户内存池
		task_struct *cur = running_thread();
		bit_idx_start = bitmap_scan(&cur->userprog_vaddr.vaddr_bitmap, pg_cnt);
		if (bit_idx_start == -1) return NULL;
		while (cnt < pg_cnt) {
			bitmap_set(&cur->userprog_vaddr.vaddr_bitmap, bit_idx_start + cnt++, 1);
		}
		vaddr_start = cur->userprog_vaddr.vaddr_start + bit_idx_start * PG_SIZE;

		/* (0xc0000000 - PG_SIZE)作为用户3级栈已经在 start_process 被分配 */
		ASSERT((uint32_t)vaddr_start < (0xc0000000 - PG_SIZE));
	}

	return (void*) vaddr_start;
}

/* 得到虚拟地址vaddr对应的pte指针(虚拟地址) */
uint32_t *pte_ptr(uint32_t vaddr) {
	// 页目录表中最后一项指向页目录表的base_addr,因此前10位应该指向页目录表最后一项
	// 中间10位应该是PDE的index,最后12位为PTE的index左移2位
	uint32_t *pte = (uint32_t*)(0xffc00000 + ((vaddr & 0xffc00000) >> 10) + PTE_INDEX(vaddr) * 4);
	return pte;
}

/* 得到虚拟地址vaddr对应的pde的指针(虚拟地址) */
uint32_t *pde_ptr(uint32_t vaddr) {
	uint32_t *pde = (uint32_t*)(0xfffff000 + ((vaddr & 0xffc00000) >> 20));
	return pde;
}

/* 在m_pool指向的物理内存池中分配1个物理页,成功则返回页框的物理地址,失败则返回NULL */
static void* palloc(pool* m_pool) {
	/* 扫描或设置位图要保证原子操作 */
	int bit_idx = bitmap_scan(&m_pool->pool_bitmap, 1); // 找一个物理页面
	if (bit_idx == -1) return NULL;

	bitmap_set(&m_pool->pool_bitmap, bit_idx, 1);
	uint32_t page_phyaddr = m_pool->phy_addr_start + bit_idx * PG_SIZE;
	return (void*) page_phyaddr;
}

/* 页表中添加虚拟地址 _vaddr 与物理地址 _page_phyaddr 的映射 */
static void page_table_add(void* _vaddr, void* _page_phyaddr) {
	uint32_t vaddr = (uint32_t) _vaddr, page_phyaddr = (uint32_t) _page_phyaddr;
	uint32_t *pde = pde_ptr(vaddr);
	uint32_t *pte = pte_ptr(vaddr);

	/************************ 注意 *************************
	 * 执行*pte,会访问到空的pde.所以确保pde创建完成后才能执行*pte,
	 * 否则会引发page_fault.因此在*pde为0时,pte只能出现在下面
	 * else语句块中的*pde后面.
	 *******************************************************/

	/* 先在页目录内判断目录项的P位,若为1,则表示该表已存在 */
	if (*pde & 0x00000001) {	 // 页目录项和页表项的第0位为P,此处判断目录项是否存在
		ASSERT(!(*pte & 0x00000001));

		if (!(*pte & 0x00000001)) {
			*pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1); // US=1,RW=1,P=1
		} else {	//目前应该不会执行到这,因为上面的ASSERT会先执行
			PANIC("pte repeat");
			*pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1);	// US=1,RW=1,P=1
		}
	} else {
		uint32_t pde_phyaddr = (uint32_t) palloc(&kernel_pool);
		*pde = (pde_phyaddr | PG_US_U | PG_RW_W | PG_P_1);

		/**
		 * 分配到的物理页地址pde_phyaddr对应的物理内存清0,避免里面的
		 * 陈旧数据变成了页表项,从而让页表混乱.访问到pde对应的物理地址,
		 * 用pte取高20位便可,因为pte基于该pde对应的物理地址内再寻址,
		 * 把低12位置0便是该pde对应的物理页的起始
		*/
		memset((void*) ((uint32_t)pte & 0xFFFFF000), 0, PG_SIZE);

		ASSERT(!(*pte & 0x00000001));
		*pte = (page_phyaddr | PG_US_U | PG_RW_W | PG_P_1); // US=1,RW=1,P=1
	}
}

/* 分配pg_cnt个页空间,成功则返回起始虚拟地址,失败时返回 NULL */
void* malloc_page(pool_flags pf, uint32_t pg_cnt) {
	ASSERT(pg_cnt > 0 && pg_cnt < 3840);
	/*********** malloc_page 的原理是三个动作的合成: ***********
	 * 1.通过vaddr_get在虚拟内存池中申请虚拟地址
	 * 2.通过palloc在物理内存池中申请物理页
	 * 3.通过page_table_add将以上得到的虚拟地址和物理地址在页表中完成映射
	 *********************************************************/

	void* vaddr_start = vaddr_get(pf, pg_cnt);
	if (vaddr_start == NULL) return NULL;

	uint32_t vaddr = (uint32_t) vaddr_start, cnt = pg_cnt;
	pool *mem_pool = pf & PF_KERNEL ? &kernel_pool : &user_pool;
	
	/* 因为虚拟地址是连续的,但物理地址可以是不连续的,所以逐个做映射 */
	while (cnt--) {
		void *page_phyaddr = palloc(mem_pool);
		if (page_phyaddr == NULL) {
			// TODO 失败时要将曾经已申请的虚拟地址和物理页全部回滚,在将来完成内存回收时再补充
			return NULL;
		}

		page_table_add((void*) vaddr, page_phyaddr);	// 在页表中做映射
		vaddr += PG_SIZE;															// 下一个虚拟页
	}

	return vaddr_start;
}
/* 从内核物理内存池中申请pg_cnt页内存,成功则返回其虚拟地址,失败则返回NULL */
void* get_kernel_pages(uint32_t pg_cnt) {
	lock_acquire(&kernel_pool.lock);
	void *vaddr = malloc_page(PF_KERNEL, pg_cnt);
	if (vaddr != NULL) {		// 若分配的地址不为空,将页框清0后返回
		memset(vaddr, 0, pg_cnt * PG_SIZE);
	}
	lock_release(&kernel_pool.lock);
	return vaddr;
}

/* 在用户空间中申请4k内存，并返回其虚拟地址 */
void *get_user_pages(uint32_t pg_cnt) {
	lock_acquire(&user_pool.lock);
	void* vaddr = malloc_page(PF_USER, pg_cnt);
	memset(vaddr, 0, pg_cnt * PG_SIZE);
	lock_release(&user_pool.lock);
	return vaddr;
}

/* 将地址 vaddr 与 pf 池中的物理地址关联，仅支持一页空间分配 */
void *get_a_page(pool_flags pf, uint32_t vaddr) {
	pool *mem_pool = pf & PF_KERNEL ? &kernel_pool : &user_pool;
	lock_acquire(&mem_pool->lock);

	/* 先将虚拟地址对应的位图置1 */
	task_struct* cur = running_thread();
	int32_t bit_idx = -1;

	if (cur->pgdir != NULL && pf == PF_USER) { // 若当前是用户进程申请用户内存,就修改用户进程自己的虚拟地址位图
		bit_idx = (vaddr - cur->userprog_vaddr.vaddr_start) / PG_SIZE;
		ASSERT(bit_idx > 0);
		bitmap_set(&cur->userprog_vaddr.vaddr_bitmap, bit_idx, 1);
	} else if (cur->pgdir == NULL && pf == PF_KERNEL){ // 如果是内核线程申请内核内存,就修改kernel_vaddr
		bit_idx = (vaddr - kernel_vaddr.vaddr_start) / PG_SIZE;
		ASSERT(bit_idx > 0);
		bitmap_set(&kernel_vaddr.vaddr_bitmap, bit_idx, 1);
	} else {
		PANIC("get_a_page:not allow kernel alloc userspace or user alloc kernelspace by get_a_page");
	}

	void* page_phyaddr = palloc(mem_pool);
	if (page_phyaddr == NULL) {
		return NULL;
	}
	page_table_add((void*)vaddr, page_phyaddr);
	lock_release(&mem_pool->lock);
	return (void*)vaddr;
}

/* 得到虚拟地址映射到的物理地址 */ 
uint32_t addr_v2p(uint32_t vaddr) {
	uint32_t *pte = pte_ptr(vaddr);
	return ((*pte & 0xfffff000) + (vaddr & 0x00000fff));
}

/* 初始化内存池 */
static void mem_pool_init(uint32_t all_mem) {
	put_str("    mem_pool_init start\n");

	// 页表大小 = 1页目录表 + 第0和第768个页目录项指向同一个页表
	//						+ 第769～1022个页目录项共指向254个页表
	uint32_t page_table_size = PG_SIZE * 256; // 0x100 * 0x1000
	uint32_t used_mem = page_table_size + 0x100000;			// 0x100000为低端1MB内存
	uint32_t free_mem = all_mem - used_mem;
	// 1页为4KB,不管总内存是不是4k的倍数
	// 对于以页为单位的内存分配策略,不足1页的内存不用考虑了
	uint16_t all_free_pages = free_mem / PG_SIZE;

	uint16_t kernel_free_pages = all_free_pages / 2;
	uint16_t user_free_pages = all_free_pages - kernel_free_pages;

	// 为简化位图操作,余数不处理,坏处是这样做会丢内存.
	// 好处是不用做内存的越界检查，因为位图表示的内存少于实际物理内存
	uint32_t kbm_length = kernel_free_pages / 8;
	uint32_t ubm_length = user_free_pages / 8;

	uint32_t kp_start = used_mem;																	// kernel_pool起始地址
	uint32_t up_start = kp_start + kernel_free_pages * PG_SIZE;		// user_pool起始地址
	
	kernel_pool.phy_addr_start = kp_start;
	user_pool.phy_addr_start = up_start;

	kernel_pool.pool_size = kernel_free_pages * PG_SIZE;
	user_pool.pool_size = user_free_pages * PG_SIZE;

	kernel_pool.pool_bitmap.btmp_bytes_len = kbm_length;
	user_pool.pool_bitmap.btmp_bytes_len = ubm_length;

	/*************** 内核内存池和用户内存池位图 *****************/
	kernel_pool.pool_bitmap.bits = (void *) MEM_BITMAP_BASE;
	// 用户内存池的位图紧跟在内核内存池位图之后
	user_pool.pool_bitmap.bits = (void *) (MEM_BITMAP_BASE + kbm_length);

	/******************** 输出内存池信息 **********************/
	put_str("        kernel_pool_bitmap_start: ");
	put_int((uint32_t) kernel_pool.pool_bitmap.bits);
	put_str(", kernel_pool_phy_addr_start: ");
	put_int(kernel_pool.phy_addr_start);
	put_str("\n");
	put_str("        user_pool_bitmap_start: ");
	put_int((uint32_t) user_pool.pool_bitmap.bits);
	put_str(", user_pool_phy_addr_start: ");
	put_int(user_pool.phy_addr_start);
	put_str("\n");

	/* 将位图置0 */
	bitmap_init(&kernel_pool.pool_bitmap);
	bitmap_init(&user_pool.pool_bitmap);

	lock_init(&kernel_pool.lock);
	lock_init(&user_pool.lock);


	/* 下面初始化内核虚拟地址的位图,按实际物理内存大小生成数组。*/
	kernel_vaddr.vaddr_bitmap.btmp_bytes_len = kbm_length;	// 用于维护内核堆的虚拟地址,所以要和内核内存池大小一致
	
	/* 位图的数组指向一块未使用的内存,目前定位在内核内存池和用户内存池之上*/
	kernel_vaddr.vaddr_bitmap.bits = (void*) (MEM_BITMAP_BASE + kbm_length + ubm_length);

	// 虚拟地址的起始地址为0xc0100000,因为物理地址0x0~0xfffff映射到了0xc0000000到0xc00fffff
	kernel_vaddr.vaddr_start = K_HEAP_START; 
	bitmap_init(&kernel_vaddr.vaddr_bitmap);
	put_str("    mem_pool_init done\n");
}

/* 内存管理部分初始化入口 */
void mem_init(void) {
	put_str("mem_init start\n");
	uint32_t mem_bytes_total = (*(uint32_t*)(0xb00));		// 0xb00中存有total_mem_bytes,是物理内存总量
	mem_pool_init(mem_bytes_total);											// 初始化内存池
	put_str("mem_init done\n");
}