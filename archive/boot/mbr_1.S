;主引导程序
;LOADER_BASE_ADDR equ 0xA000
;LOADER_START_SECTOR equ 0x2
;------------------------------------------------------------------------------
SECTION MBR vstart=0x7c00
	mov ax, cs
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov sp, 0x7c00
	mov ax, 0xb800
	mov gs, ax

; 0x10号中断负责打印有关的例程
;------------------------------------------------------------------------------
; INT 0x10 功能号:0x06 功能描述:上卷窗口
;------------------------------------------------------------------------------
;利用0x06号功能清屏
;输入
;AH 功能号=0x06
;AL 上卷的行数,0为全部
;BH 上卷行属性
;(CL,CH) = 窗口左上角的(X,Y)位置
;(DL,DH) = 窗口右下角的(X,Y)位置
; 无返回值
mov ax, 0x600
mov bx, 0x700
mov cx, 0 			; 左上角: (0, 0)
mov dx, 0x184f 	; 右下角: (80,25)
								; VGA 文本模式中,一行只能容纳80个字符,共25行
int 0x10

;;;;;;;;; 打印字符串 ;;;;;;;;;;;;;;;;
mov byte [gs:0x00], '1'
mov byte [gs:0x01], 0xA4

mov byte [gs:0x02], ' '
mov byte [gs:0x03], 0xA4

mov byte [gs:0x04], 'M'
mov byte [gs:0x05], 0xA4

mov byte [gs:0x06], 'B'
mov byte [gs:0x07], 0xA4

mov byte [gs:0x08], 'R'
mov byte [gs:0x09], 0xA4

;;;;;;;;; 打字字符串结束 ;;;;;;;;;;;;;;;

jmp $

times 510 - ($ - $$) db 0
db 0x55, 0xaa