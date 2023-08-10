section .data
str_c_lib: db	"c library says: hello world!", 0xa			;0xa 为 LF ASCII 码	
str_c_lib_len equ $-str_c_lib

str_syscall: db	"syscall says: hello world!", 0xa
str_syscall_len equ $-str_syscall

section .text
global _start
_start:
;;;;;;;;;;;;; 方式 1: 模拟 C 语言中系统调用库函数 write ;;;;;;;;;;;;;
push str_c_lib_len								;按照C调用约定压入参数
push str_c_lib
push 1

call simu_write										;调用下面定义的simu_write
add esp, 12												;回收栈空间



;;;;;;;;;;;;; 方式 2: 跨过库函数，直接进行系统调用 ;;;;;;;;;;;;;
mov eax, 4												;第4号子功能是write系统调用(不是C库函数write)
mov ebx, 1
mov ecx, str_syscall
mov edx, str_syscall_len
int 0x80													;发起中断，通知 Linux 完成请求的功能

;;;;;;;;;;;;; 退出程序 ;;;;;;;;;;;
mov eax, 1												;第1号子功能是exit
int 0x80													;发起中断，通知 Linux 完成请求的功能

simu_write:
push rbp
mov rbp, rsp
mov eax, 4
mov ebx, [rbp+16]
mov ecx, [rbp+24]
mov edx, [ebp+32]
int 0x80 
pop rbp
ret