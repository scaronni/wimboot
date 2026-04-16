/*
 * Copyright (C) 2024 Simone Caronni
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */

/**
 * @file
 *
 * EFI handover protocol entry point
 *
 * When GRUB boots wimboot via the "linux" command on EFI, it uses the
 * Linux EFI handover protocol.  GRUB strips the setup sectors and
 * loads only the payload (PE binary minus headers) into memory, then
 * jumps to the handover entry.
 *
 * Because PE relocations are not applied by GRUB, this stub must be
 * fully position-independent.  It reconstructs the complete PE binary
 * by concatenating the PE header (preserved in boot_params by GRUB)
 * with the payload, then calls EFI LoadImage/StartImage so the
 * firmware properly loads wimboot with relocations applied.
 */

#if defined(__x86_64__)

/* EFI_SYSTEM_TABLE field offsets (x86_64) */
#define SYSTAB_BOOT_SERVICES	0x60

/* EFI_BOOT_SERVICES field offsets (x86_64) */
#define BS_ALLOCATE_POOL	0x40
#define BS_FREE_POOL		0x48
#define BS_LOAD_IMAGE		0xc8
#define BS_START_IMAGE		0xd0

/* EFI memory type */
#define EFI_LOADER_DATA		2

	.section ".note.GNU-stack", "", @progbits
	.text
	.globl	efi_handover
	.type	efi_handover, @function

/*
 * EFI handover entry point
 *
 * Called by GRUB with MS x64 ABI:
 *   RCX = parent image handle (GRUB's EFI image handle)
 *   RDX = EFI system table pointer
 *   R8  = boot params (contains first _prefix_len bytes of the file,
 *          including the MZ/PE headers)
 *
 * Stack layout after prologue (rsp offsets):
 *   0x00-0x1f  shadow space for callees
 *   0x20-0x27  stack argument slot 5 (LoadImage: SourceSize)
 *   0x28-0x2f  stack argument slot 6 (LoadImage: &ImageHandle)
 *   0x30-0x37  local: pe_size
 *   0x38-0x3f  local: buffer pointer
 *   0x40-0x47  local: image handle
 *   0x48-0x5f  padding
 */
efi_handover:
	/* Save MS ABI non-volatile registers */
	pushq	%rbx
	pushq	%rsi
	pushq	%rdi
	pushq	%r12
	pushq	%r13
	pushq	%r14
	pushq	%r15
	subq	$0x60, %rsp

	/* Save arguments in non-volatile registers */
	movq	%rcx, %r12		/* r12 = parent_handle */
	movq	%rdx, %r13		/* r13 = systab */
	movq	%r8, %r14		/* r14 = boot_params */
	movq	SYSTAB_BOOT_SERVICES(%r13), %r15  /* r15 = BootServices */

	/*
	 * Compute the address where GRUB loaded the payload.
	 * _efi_handover_raw_offset is our offset within the payload,
	 * so: kernel_addr = runtime_addr(efi_handover) - offset
	 */
	leaq	efi_handover(%rip), %rbx
	movl	$_efi_handover_raw_offset, %eax
	subq	%rax, %rbx		/* rbx = kernel_addr (payload base) */

	/*
	 * Total PE size = _prefix_len (PE header from setup area)
	 *               + _payload_len (sections loaded by GRUB)
	 */
	movl	$_prefix_len, %eax
	movl	$_payload_len, %ecx
	addq	%rcx, %rax
	movq	%rax, 0x30(%rsp)	/* save pe_size */

	/*
	 * Allocate buffer for the reconstructed PE binary.
	 * AllocatePool(EfiLoaderData, pe_size, &buffer)
	 */
	leaq	0x38(%rsp), %r8		/* arg3: &buffer */
	movq	%rax, %rdx		/* arg2: pe_size */
	movl	$EFI_LOADER_DATA, %ecx	/* arg1: memory type */
	call	*BS_ALLOCATE_POOL(%r15)
	testq	%rax, %rax
	jnz	.Lfail

	/*
	 * Reconstruct the full PE binary by concatenating:
	 * 1. The PE header from boot_params (first _prefix_len bytes)
	 * 2. The payload from GRUB's loaded data
	 */
	cld
	movq	0x38(%rsp), %rdi	/* dst = buffer */
	movq	%r14, %rsi		/* src = boot_params (PE header) */
	movl	$_prefix_len, %ecx
	rep	movsb			/* rdi = buffer + _prefix_len */

	movq	%rbx, %rsi		/* src = kernel_addr (payload) */
	movl	$_payload_len, %ecx
	rep	movsb

	/*
	 * Load the PE image via EFI LoadImage.
	 * LoadImage(FALSE, parent_handle, NULL, buffer, pe_size, &handle)
	 */
	movq	$0, 0x40(%rsp)		/* image_handle = NULL */
	leaq	0x40(%rsp), %rax
	movq	%rax, 0x28(%rsp)	/* stack arg6: &image_handle */
	movq	0x30(%rsp), %rax
	movq	%rax, 0x20(%rsp)	/* stack arg5: pe_size */
	movq	0x38(%rsp), %r9		/* arg4: SourceBuffer */
	xorq	%r8, %r8		/* arg3: DevicePath = NULL */
	movq	%r12, %rdx		/* arg2: ParentImageHandle */
	xorq	%rcx, %rcx		/* arg1: BootPolicy = FALSE */
	call	*BS_LOAD_IMAGE(%r15)
	testq	%rax, %rax
	jnz	.Lfree

	/*
	 * Start the loaded image.
	 * StartImage(image_handle, NULL, NULL)
	 */
	movq	0x40(%rsp), %rcx	/* arg1: ImageHandle */
	xorq	%rdx, %rdx		/* arg2: ExitDataSize = NULL */
	xorq	%r8, %r8		/* arg3: ExitData = NULL */
	call	*BS_START_IMAGE(%r15)

.Lfree:
	/* Free the reconstructed PE buffer */
	movq	0x38(%rsp), %rcx
	call	*BS_FREE_POOL(%r15)

.Lfail:
	/* Restore non-volatile registers and return */
	addq	$0x60, %rsp
	popq	%r15
	popq	%r14
	popq	%r13
	popq	%r12
	popq	%rdi
	popq	%rsi
	popq	%rbx
	ret

	.size	efi_handover, . - efi_handover

#endif /* __x86_64__ */
