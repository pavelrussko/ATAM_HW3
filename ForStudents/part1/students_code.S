.global	compute_char_repeats, parse_lines

.section .text
compute_char_repeats:
	push %rbp
	mov %rsp, %rbp
	cmpq $0, %rsi
	je end
	movq %rdi, %r8 # Current address
	movq %rsi, %r9 # Counter_length
	movq $0, %rax # result = 0
.loop_check:
	cmpq $0, %r9
	jle end
# Loop body
	cmpb %dl, (%r8)
	jne not_special
	incq %rax
not_special:
	incq %r8
	decq %r9
	jmp .loop_check
end:
	movq %rbp, %rsp
	pop %rbp
	ret

parse_lines:
	push %rbp
	movq %rsp, %rbp
	push %rbx
	push %r12
	push %r13
	push %r14
	push %r15

	subq $144, %rsp
	movq %rdi, %r12 # Path
	movq %rsi, %r13 # Pointer to max_length
	movq %rdx, %r14 # Max repeat
	movq $0, %r15 # Counter of lines
	leaq -144(%rbp), %rbx # Current address
	movq $0, (%r13)
	movq $0, (%r14)
get_special:
	call get_the_special_char
	movq %rax, -16(%rbp) # Special char
open:
	movq $257, %rax
	movq $-100, %rdi
	movq %r12, %rsi
	movq $0, %rdx
	movq $0, %r10
	syscall
	movq %rax, -8(%rbp) # fd
	# Check if succeed to open
	cmpq $0, %rax
	jl error
read_and_write_byte:
	movq $0, %rax
	movq -8(%rbp), %rdi
	movq %rbx, %rsi
	movq $1, %rdx
	syscall
check_empty_line:
	cmpq $0, %rax
	jl error
	cmpq $0, %rax
	je eof
	cmpb $'\n', (%rbx)
	je end_of_line
	
	incq %rbx
	jmp read_and_write_byte

end_of_line:
	movq %rbx, %r10
	leaq -144(%rbp), %r11
	subq %r11, %r10 # length of current line
	cmpq (%r13), %r10
	jle not_longest
	movq %r10, (%r13)
not_longest:
	leaq -144(%rbp), %rdi
	movq %r10, %rsi
	movq -16(%rbp), %rdx
	call compute_char_repeats
	cmpq (%r14), %rax
	jle not_most_repeated
	movq %rax, (%r14)
not_most_repeated:
	incq %r15
	leaq -144(%rbp), %rbx
	jmp read_and_write_byte
error:
	#close file
	movq $3, %rax
	#move fd to rdi
	movq -8(%rbp), %rdi
	syscall
	ret
eof:
	movq %rbx, %r10
	leaq -144(%rbp), %r11
	subq %r11, %r10 # length of current line
	cmpq (%r13), %r10
	jle not_longest_eof
	movq %r10, (%r13)
not_longest_eof:
	leaq -144(%rbp), %rdi
	movq %r10, %rsi
	movq -16(%rbp), %rdx
	call compute_char_repeats
	cmpq (%r14), %rax
	jle not_most_repeated_eof
	movq %rax, (%r14)
not_most_repeated_eof:
	cmpq $0, %r10
	je dont_increment
	incq %r15
dont_increment:
	#close file
	movq $3, %rax
	#move fd to rdi
	movq -8(%rbp), %rdi
	syscall
	movq %r15, %rax
	addq $144, %rsp
	pop %r15
	pop %r14
	pop %r13
	pop %r12
	pop %rbx
	pop %rbp
	ret
