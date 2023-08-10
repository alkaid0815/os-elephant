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

mov byte [gs:160], 'P'

jmp $