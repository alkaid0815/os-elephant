;主引导程序
;------------------------------------------------------------------------------
%include "boot.inc"
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

mov eax, LOADER_START_SECTOR 	;起始LBA扇区号
mov bx, LOADER_BASE_ADDR			;写入的地址
mov cx, 4											;待读入的扇区数
call rd_disk_m_16							

jmp LOADER_BASE_ADDR + 0x300

;------------------------------------------------------------------------------
;功能:读取硬盘的n个扇区
rd_disk_m_16:
;------------------------------------------------------------------------------
																	;eax = LBA扇区号
																	;bx = 将数据写入的内存地址
																	;cx = 读取的扇区数
mov esi, eax			;备份eax
mov di, cx

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
mov [bx], ax
add bx, 2
loop .go_on_read
ret

times 510 - ($ - $$) db 0
db 0x55, 0xaa