;加载器
;------------------------------------------------------------------------------
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR

;构建GDT和其内部的描述符
GDT_BASE: dd 	0x00000000
					dd	0x00000000

CODE_DESC: 	dd 0x0000FFFF
						dd DESC_CODE_HIGH4

DATA_STACK_DESC: 	dd 0x0000FFFF	
									dd DESC_DATA_HIGH4

VIDEO_DESC:		dd 0x80000007 ;limit=(0xbffff-0xb8000)/4k=0x7,base=0xb8000
							dd DESC_VIDEO_HIGH4 ;此时dpl为0

GDT_SIZE equ $ - GDT_BASE
GDT_LIMIT equ GDT_SIZE - 1
times 60 dq 0 ;此处预留60个描述符的空位

;total_mem_bytes用于保存内存容量,以byte为单位
;当前偏移loader.bin文件头0x200字节
;loader.bin的加载地址是0x900
;故total_mem_bytes内存中的地址是0xb00
total_mem_bytes dd 0

SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA equ (0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0

;以下是gdt的指针,前2字节是gdt界限,后4字节是gdt起始地址
gdt_ptr dw GDT_LIMIT
				dd GDT_BASE

;人工对齐: total_mem_bytes4+gdt_ptr6+ards_buf244+ards_nr2共256字节
ards_buf times 244 db 0
ards_nr dw 0	;用于记录ARDS结构体数量

loader_start:

;-------------------- 获取物理内存容量 -------------------------------

;========= int 0x15, eax = 0xE820, edx = 534D4150h('SMAP')获取内存布局 =========
xor ebx, ebx									;第一次调用时, ebx的值需要为0
mov edx, 0x534D4150						;edx只赋值一次, 循环体中不会改变
mov di, ards_buf							;ards结构缓冲区, es此时已经为0

.e820_mem_get_loop:
mov eax, 0x0000e820					;执行int 0x15后, eax值变为0x534d4150, 因此每次循环都要重置
mov ecx, 20										;ARDS地址范围描述符结构大小是20字节
int 0x15
jc .e820_failed_so_try_e801		;CF位为1代表有错误,就跳转尝试第二种方法
add di, cx										;使di增加20字节指向缓冲区中新的ARDS结构位置
inc word [ards_nr]						;更新ARDS数量
cmp ebx, 0										;若ebx为0且cf不为 1, 这说明ards全部返回
jnz .e820_mem_get_loop

;在有所ards中,找出(base_add_low + length_low)的最大值,即内存的容量
mov cx, [ards_nr]							;循环次数
mov ebx, ards_buf
xor edx, edx									;edx 为最大的内存容量,在此先清 0
.find_max_mem_area:
mov eax, [ebx]								;base_add_low
add eax, [ebx+8]							;length_low
add ebx, 20										;指向缓冲区中下一个ARDS结构
cmp edx, eax
jge .next_ards
mov edx, eax
.next_ards:
loop .find_max_mem_area
jmp .mem_get_ok

;========= int 0x15, eax = 0xE801 获取内存大小, 最大支持4G =========
.e820_failed_so_try_e801:
 mov ax, 0xe801
 int 0x15
 jc .e801_failed_so_try88			;CF位为1代表有错误,就跳转尝试第三种方法

 ;1. 先算出低 15MB 的内存
 ;	 ax和cx中是以KB为单位的内存数量, 将其转换为以byte为单位
 mov cx, 0x400								;0x400=1024
 mul cx												;乘积为32位在dx:ax中
 shl edx,16
 and eax,0x0000FFFF
 or edx,eax										;将乘积拼凑在edx中
 add edx, 0x100000						;ax只是15MB, 故要加1MB
 mov esi, edx									;先把低15MB的内存容量存入esi寄存器备份

;2. 再将16MB以上的内存转换为byte为单位
; 	寄存器bx和dx中是以64KB为单位的内存数量
xor eax, eax
mov ax, bx
mov ecx, 0x10000							;0x10000十进制为64KB
mul ecx												;乘积的低32位存入eax
add esi, eax									;由于此方法只能测出4GB以内的内存, 故32位eax足够了
mov edx, esi
jmp .mem_get_ok

;========= int 0x15, ah = 0x88 获取内存大小, 只能获取64MB之内 =========
.e801_failed_so_try88:
;int 0x15后,ax存入的是以KB为单位的内存容量
mov ah, 0x88
int 0x15
jc .error_hlt							
and eax,0x0000FFFF

;16位乘法, 被乘数是ax,积为32位.积的高16位在dx中,积的低16位在ax中
mov cx, 0x400
mul cx
shl edx, 16
or edx, eax
add edx, 0x100000							;0x88子功能只会返回1MB以上的内存,故实际内存大小要加上1MB

.mem_get_ok:
mov [total_mem_bytes], edx


;-------------------- 准备进入保护模式 -------------------------------
;1 打开 A20
;2 加载 gdt
;3 将cr0的pe位置1

;----------------- 打开 A20 ----------------
in al, 0x92
or al, 0000_0010B
out 0x92, al

;----------------- 加载 GDT ----------------
lgdt [gdt_ptr]

;-------------- 将cr0的pe位置1 --------------
mov eax, cr0
or eax, 1	;设置PE位
mov cr0, eax

;此时已经在保护模式下.
;实模式下段描述符缓冲寄存器的limit默认为0xFFFF
jmp dword SELECTOR_CODE:p_mode_start ;刷新流水线

.error_hlt:		      ;出错则挂起
hlt

[bits 32]
p_mode_start:
mov ax, SELECTOR_DATA
mov ds, ax
mov es, ax
mov ss, ax
mov esp,LOADER_STACK_TOP
mov ax, SELECTOR_VIDEO
mov gs, ax

; -------------------------   加载kernel  ----------------------
mov eax, KERNEL_START_SECTOR						;kernel.bin所在的扇区号
mov ebx, KERNEL_BIN_BASE_ADDR						;从磁盘读出后，写入到ebx指定的地址
mov ecx, 200 														;读入的扇区数

call rd_disk_m_32

; -------------------------   开启页表  ----------------------

;创建页目录及页表并初始化页内存位图
call setup_page

;要将描述符表地址及偏移量写入内存gdt_ptr,一会儿用新地址重新加载
sgdt [gdt_ptr]						;存储到原来gdt所有的位置

;将gdt描述符中视频段描述符中的段基址+0xc0000000 
mov ebx, [gdt_ptr + 2]
;视频段是第3个段描述符,每个描述符是8字节,故0x18
;段描述符的高4字节的最高位是段基址的第31～24位
or dword [ebx + 0x18 + 4], 0xc0000000

;将gdt的基址加上0xc0000000使其成为内核所在的高地址
add dword [gdt_ptr + 2], 0xc0000000

add esp, 0xc0000000 ;将栈指针同样映射到内核地址

;把页目录地址赋给cr3
mov eax, PAGE_DIR_TABLE_POS
mov cr3, eax

;打开cr0的PG位(第31位)
mov eax, cr0,
or  eax, 0x80000000
mov cr0, eax

;----------------- 分页已开启 -----------------

;在开启分页后,用gdt新的地址重新加载
lgdt [gdt_ptr]										;重新加载
jmp SELECTOR_CODE:enter_kernel	  ;强制刷新流水线,更新gdt

enter_kernel:
call kernel_init
mov esp, 0xc009f000
jmp KERNEL_ENTRY_POINT 						;进入内核

;---------- 将kernel.bin中的segment拷贝到编译的地址----------
kernel_init:
xor eax, eax
xor ebx, ebx											;ebx记录程序头表地址
xor ecx, ecx											;cx记录程序头表中的program header数量
xor edx, edx											;dx记录program header尺寸,即e_phentsize

mov dx, [KERNEL_BIN_BASE_ADDR + 42] 				;偏移文件42字节处的属性是e_phentsize,表示program header大小
mov ebx, [KERNEL_BIN_BASE_ADDR + 28] 				;偏移文件开始部分28字节的地方是e_phoff,表示第1个program header在文件中的偏移量
add ebx, KERNEL_BIN_BASE_ADDR

mov cx, [KERNEL_BIN_BASE_ADDR + 44]					;e_phnum,program header数量

.each_segment:
cmp byte [ebx+0], PT_NULL										;若p_type等于PT_NULL,说明此program header未使用
je .PTNULL

;为函数memcpy压入参数,参数是从右往左依然压入
;函数原型类似于memcpy(dst, src, size)
push dword [ebx + 16]						;p_filesz->size

mov eax, [ebx + 4]							;p_offset
add eax, KERNEL_BIN_BASE_ADDR		;src
push eax
push dword [ebx + 8]						;dst

call mem_cpy										;调用mem_cpy完成段复制
add esp, 12											;清理栈中压入的三个参数

.PTNULL:
add ebx, edx																;edx为program header大小,即 e_phentsize
																						;在此ebx指向下一个program header
loop .each_segment
ret

;---------- 逐字节拷贝 memcpy (dst, src, size) ------------
;输入:栈中三个参数 (dst, src, size)
;输出:无
;---------------------------------------------------------
mem_cpy:
cld													;清零DF
push ebp
mov ebp, esp
push ecx										;rep指令用到了ecx,但ecx对于外层段的循环还有用,故先入栈备份

;第一个参数的offset为8 = sizeof ebp + sizeof eip
mov edi, [ebp + 8] 					;dst
mov esi, [ebp + 12]					;src
mov ecx, [ebp + 16] 				;size
rep movsb		;逐字节拷贝

;恢复环境
pop ecx
pop ebp
ret


;------------- 创建页目录及页表 -------------
;以PAGE_DIR_TABLE_POS为起始地址,第一个4kb为页目录表,之后每个4kb为一个页表
setup_page:
;先把页目录占用的空间逐字节清 0
mov ecx, 4096
mov esi, 0
.clear_page_dir:
mov byte [PAGE_DIR_TABLE_POS + esi], 0
inc esi
loop .clear_page_dir

;开始创建页目录项(PDE)
.create_pde:						;创建 Page Directory Entry
mov eax, PAGE_DIR_TABLE_POS
add eax, 0x1000					;此时eax为第一个页表的位置及属性
mov ebx, eax						;此处为ebx赋值,是为.create_pte做准备,ebx为基址


;下面将页目录项0和0xc00都存为第一个页表的地址,每个页表表示4MB内存
;这样0xc03fffff以下的地址和0x003fffff以下的地址都指向相同的页表
;这是为将地址映射为内核地址做准备
or eax, PG_US_U | PG_RW_W | PG_P
;在页目录表中的第1个目录项写入第一个页表的位置(0x101000)及属性(7)
mov [PAGE_DIR_TABLE_POS + 0x0], eax		;第一个目录项

;一个页表项占用4字节,0xc00表示第768个页表占用的目录项,0xc00以上的目录项用于内核空间
;也就是页表的0xc0000000～0xffffffff共计1G属于内核
;0x0～0xbfffffff共计3G属于用户进程
mov [PAGE_DIR_TABLE_POS + 0xc00], eax
sub eax, 0x1000
mov [PAGE_DIR_TABLE_POS + 4092], eax ;使最后一个目录项指向页目录表自己的地址

;下面创建页表项(PTE)
;设置1M低端内存
mov ecx, 256 													;1M低端内存/每页大小4k=256
mov esi, 0
mov edx, PG_US_U | PG_RW_W | PG_P			;属性为7,US=1,RW=1,P=1
.create_pte:													;创建 Page Table Entry
mov [ebx+esi*4], edx									;此时的ebx已经在上面通过eax赋值为0x101000,也就是第一个页表的地址
add edx, 4096													;增加4kb
inc esi
loop .create_pte

;创建内核其他页表的PDE:
;提前把内核页表固定下来,这样之后内核内存不够,就不需要创建新的页表,
;因此不需要重新设置每一个用户进程对应这个新创建的页表的PDE
mov eax, PAGE_DIR_TABLE_POS
add eax, 0x2000												;此时eax为第二个页表的位置
or eax, PG_US_U | PG_RW_W | PG_P 			;页目录项的属性US,RW和P位都为1
mov ebx, PAGE_DIR_TABLE_POS
mov ecx, 254													;范围为第769～1022的所有目录项数量
mov esi, 769
.create_kernel_pde:
mov [ebx+esi*4], eax
add eax, 0x1000
loop .create_kernel_pde
ret


;------------------------------------------------------------------------------
;功能:读取硬盘的n个扇区
rd_disk_m_32:	   
;-------------------------------------------------------------------------------
																							; eax=LBA扇区号
																							; ebx=将数据写入的内存地址
																							; ecx=读入的扇区数
mov esi, eax	   ; 备份eax
mov di, cx		   ; 备份扇区数到di

;读写硬盘:
;第一步:设置要读取的扇区数
mov dx, 0x1f2
mov al, cl
out dx, al				;读取的扇区数

mov eax, esi			;恢复eax

;第二步:将LBA地址存入 0x1f3 ～ 0x1f6

;LBA地址7～0位写入端口0x1f3
mov dx, 0x1f3
out dx, al

;LBA地址15～8位写入端口0x1f4
inc dx
mov cl, 8
shr eax, cl
out dx, al

;LBA地址23～16位写入端口0x1f5
inc dx
shr eax, cl
out dx, al

;LBA模式,主硬盘,LBA地址27-24写入端口0x1f6
inc dx
shr eax, cl
and al, 0x0f			;保留al最后4位
or al, 0xe0				;设置7~4位为1110,表示lba模式
out dx, al

;第三步:向0x1f7端口写入读命令,0x20
inc dx
mov al, 0x20
out dx, al

;至此,硬盘控制器便从指定的lba地址(eax)处,读出连续的cx个扇区,下面检查硬盘状态,不忙就能把这cx个扇区的数据读出来

;第四步:检测硬盘状态
.not_ready:
nop
in al, dx
and al, 0x88 			;保留位7和位3.位7为1表示硬盘忙,位3为1表示硬盘准备好数据了	
cmp al, 0x08
jnz .not_ready		;若未准备好,继续等

;第五步:从0x1f0端口读数据
mov ax, di				;恢复cx,即要读取的扇区数
mov dx, 256				;一次读取一个word,因此一个512byte的扇区需要读取256次
mul dx,						
mov cx, ax
mov dx, 0x1f0

.go_on_read:
in ax, dx
mov [ebx], ax
add ebx, 2
loop .go_on_read
ret

