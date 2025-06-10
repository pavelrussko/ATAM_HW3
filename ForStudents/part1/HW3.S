.global	compute_char_repeats, parse_lines

.section .text
compute_char_repeats:
    push %rbp
    mov %rsp, %rbp
    
    # Parameter validation
    cmpq $0, %rdi       # Check if buffer pointer is NULL
    je end
    cmpq $0, %rsi       # Check if length is 0
    je end
    
    # Extract the special character from rdx into a byte register
    # In x86-64 calling convention, the third arg is in rdx
    movb %dl, %r10b     # Save special char in r10b
    
    movq %rdi, %r8      # Current address
    movq %rsi, %r9      # Counter_length
    movq $0, %rax       # result = 0
    
.loop_check_repeats:
    cmpq $0, %r9
    jle end
    
    # Loop body
    cmpb %r10b, (%r8)   # Compare with special char in r10b
    jne not_special
    incq %rax
    
not_special:
    incq %r8
    decq %r9
    jmp .loop_check_repeats
    
end:
    movq %rbp, %rsp
    pop %rbp
    ret

.section .text
.global parse_lines
parse_lines:
    # Prologue
    push    %rbp
    mov     %rsp, %rbp
    push    %rbx
    push    %r12
    push    %r13
    push    %r14
    push    %r15

    # Arguments validation
    #   %rdi = path (char *)
    #   %rsi = pointer to max_line_length (uint64_t *)
    #   %rdx = pointer to max_repeat      (uint64_t *)
    test    %rdi, %rdi
    jz      error_invalid_params
    test    %rsi, %rsi
    jz      error_invalid_params
    test    %rdx, %rdx
    jz      error_invalid_params
    
    mov     %rdi, %r12       # %r12 = path
    mov     %rsi, %r13       # %r13 = pointer to max_line_length
    mov     %rdx, %r14       # %r14 = pointer to max_repeat
    mov     $-1, %rbx        # Initialize fd to invalid value
    xor     %r15, %r15       # Initialize line counter to 0

    # Get the special character
    call    get_the_special_char
    movb    %al, %r10b       # Store special char in r10b for later use

    # Open file (openat)
    mov     $257, %rax       # sys_openat
    mov     $-100, %rdi      # AT_FDCWD
    mov     %r12, %rsi       # path
    mov     $0, %rdx         # O_RDONLY
    mov     $0, %r10         # mode unused
    syscall
    mov     %rax, %rbx       # rbx = fd
    cmp     $0, %rbx         # Check for any error (negative values)
    jl      error

    # Allocate two 128-byte buffers on stack
    sub     $256, %rsp
    lea     (%rsp), %r10     # r10 = current_line buffer base
    lea     128(%rsp), %r11  # r11 = longest_line buffer base

    xor     %rcx, %rcx       # rcx = max_line_length = 0
    mov     %r10, %r8        # r8 = write pointer into current_line

read_loop:
    # Check buffer overflow BEFORE reading
    mov     %r8, %rax
    sub     %r10, %rax
    cmp     $126, %rax       # Leave room for at least one more byte + null terminator
    jae     buffer_overflow

    # Read one byte
    mov     $0, %rax         # sys_read
    mov     %rbx, %rdi       # fd
    mov     %r8, %rsi        # buf
    mov     $1, %rdx         # len = 1
    syscall
    cmp     $0, %rax
    je      check_last_line
    cmp     $0, %rax         # Check for any read error
    jl      error

    # Check for newline
    cmpb    $'\n', (%r8)
    je      process_line

    # Advance pointer (we already checked for overflow)
    inc     %r8
    jmp     read_loop

process_line:
    # Increment line counter
    inc     %r15

    # Compute current line length: rax = r8 - r10
    mov     %r8, %rax
    sub     %r10, %rax

    # If longer than max, copy into longest buffer
    cmp     %rcx, %rax
    jle     reset_line
    
    # Validate copy operation won't overflow destination
    cmp     $128, %rax
    jae     buffer_overflow
    
    mov     %rax, %rcx       # rcx = new max length
    
    # Store null terminator for safety 
    movb    $0, (%r8)
    
    # Safe string copy
    mov     %r10, %rdi       # src = current_line
    mov     %r11, %rsi       # dst = longest_line
    mov     %rax, %rdx       # count = length
    cld
    rep     movsb

reset_line:
    # Start new current_line
    mov     %r10, %r8
    jmp     read_loop

check_last_line:
    # Check if there's unprocessed data (partial line without newline)
    mov     %r8, %rax
    sub     %r10, %rax
    test    %rax, %rax
    jz      eof
    
    # We have a partial last line - process it
    inc     %r15
    
    # Compare length with max seen
    cmp     %rcx, %rax
    jle     eof
    
    # This is the longest line - copy it
    mov     %rax, %rcx
    
    # Null-terminate for safety
    movb    $0, (%r8)
    
    # Copy to longest line buffer
    mov     %r10, %rdi
    mov     %r11, %rsi
    mov     %rax, %rdx
    cld
    rep     movsb

eof:
    # Close file
    mov     $3, %rax         # sys_close
    mov     %rbx, %rdi
    syscall
    mov     $-1, %rbx        # Mark as closed

    # Store max_line_length (we already validated %r13 is not NULL)
    mov     %rcx, (%r13)
    test    %rcx, %rcx
    je      no_lines

    # Count special-character repeats in longest line
    # Additional validation: ensure we have valid data
    test    %r11, %r11
    jz      no_lines
    
    mov     %r11, %rdi       # buf
    mov     %rcx, %rsi       # len
    movzx   %r10b, %rdx      # special char from get_the_special_char (zero-extend byte to quad)
    call    compute_char_repeats
    mov     %rax, (%r14)     # Store result
    jmp     done

no_lines:
    # No lines found: zero out repeat count
    movq    $0, (%r14)
    jmp     done

buffer_overflow:
    # Handle buffer overflow error
    # This is a specific error case, so we'll set outputs to 0 and return 0
    movq    $0, (%r13)
    movq    $0, (%r14)
    xor     %r15, %r15       # Return value = 0 lines
    jmp     cleanup

error:
    # On any error: set both outputs to 0
    movq    $0, (%r13)
    movq    $0, (%r14)
    xor     %r15, %r15       # Return value = 0 lines
    jmp     cleanup

error_invalid_params:
    # Can't safely write to output pointers if they're NULL
    xor     %r15, %r15       # Return value = 0 lines
    jmp     cleanup

cleanup:
    # Close file if it was opened
    cmp     $0, %rbx         # Check if fd is valid (>= 0)
    jl      skip_close
    mov     $3, %rax         # sys_close
    mov     %rbx, %rdi
    syscall
    
skip_close:
    # Restore stack
    add     $256, %rsp

done:
    # Set return value to number of lines
    mov     %r15, %rax
    
    # Epilogue - restore registers
    pop     %r15
    pop     %r14
    pop     %r13
    pop     %r12
    pop     %rbx
    mov     %rbp, %rsp
    pop     %rbp
    ret
