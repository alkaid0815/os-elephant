;加载器
;------------------------------------------------------------------------------
%include "boot.inc"
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR
jmp loader_start

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

SELECTOR_CODE equ (0x0001 << 3) + TI_GDT + RPL0
SELECTOR_DATA equ (0x0002 << 3) + TI_GDT + RPL0
SELECTOR_VIDEO equ (0x0003 << 3) + TI_GDT + RPL0

;以下是gdt的指针,前2字节是gdt界限,后4字节是gdt起始地址
gdt_ptr dw GDT_LIMIT
				dd GDT_BASE

loadermsg db '2 loader in real.'

loader_start:

;-----------------------------------------------------------
;INT 0x10 功能号:0x13 功能描述:打印字符串 
;-----------------------------------------------------------
;输入:
;AH 子功能号=13H
;BH = 页码
;BL = 属性(若 AL=00H 或 01H)
;CX=字符串长度
;(DH ､ DL)=坐标(行 ､ 列)
;ES:BP=字符串地址
;AL=显示输出方式
; 0—字符串中只含显示字符，其显示属性在 BL 中
;显示后，光标位置不变
; 1—字符串中只含显示字符，其显示属性在 BL 中
;显示后，光标位置改变
; 2—字符串中含显示字符和显示属性。显示后，光标位置不变
; 3—字符串中含显示字符和显示属性。显示后，光标位置改变
;无返回值
mov sp, LOADER_BASE_ADDR
mov bp, loadermsg ; ES:BP = 字符串地址
mov cx, 17				; CX = 字符串长度
mov ax, 0x1301
mov bx, 0x001f
mov dx, 0x1800
int 0x10					; 10号中断


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