/*
 * Copyright (C) 2012 Michael Brown <mbrown@fensystems.co.uk>.
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
 * bzImage prefix
 *
 */

#include "wimboot.h"

/* Refer to i386 symbols as needed */
#if __x86_64__
#define i386(symbol) __i386_ ## symbol
#else
#define i386(symbol) symbol
#endif

/** Standard number of setup sectors */
#define SETUP_SECTS 4

/** Sector size */
#define SECTOR_SIZE 512

/** Setup code length */
#define SETUP_LEN ( ( SETUP_SECTS + 1 ) * SECTOR_SIZE )

/** Protected-mode code will be loaded high */
#define LOADED_HIGH 0x01

/** Protected-mode code will be loaded to this linear address */
#define LOADED_HIGH_ADDRESS 0x100000

/** xloadflags: kernel is 64-bit */
#define XLF_KERNEL_64 0x0001

/** xloadflags: 64-bit EFI handover protocol supported */
#define XLF_EFI_HANDOVER_64 0x0008

/** Protected-mode bit in CR0 */
#define CR0_PE 0x01

/** 32-bit protected mode code segment based at real-mode %cs:0000 */
#define PREFIX_CS 0x08

/** 32 bit protected mode flat code segment */
#define PREFIX_FLAT_CS 0x10

/** 32 bit protected mode flat data segment */
#define PREFIX_FLAT_DS 0x18

	.section ".note.GNU-stack", "", @progbits
	.text
	.section ".prefix", "ax", @progbits
	.org	0
_prefix:

#if defined(__i386__) || defined(__x86_64__)

	.code32
	.arch	i386

	.org	0x1f1
setup_sects:
	.byte	SETUP_SECTS

	.org	0x1fe
boot_flag:
	.word	0xaa55

	.org	0x200
jump:
	.byte	0xeb, setup - 1f
1:

	.org	0x202
header:
	.ascii	"HdrS"

	.org	0x206
version:
	.word	0x020c	/* Version 2.12 */

	.org	0x20e
kernel_version:
	.word	( version_string - _prefix - 0x200 )

	.org	0x211
loadflags:
	.byte	LOADED_HIGH

	.org	0x218
ramdisk_image:
	.long	0	/* Filled in by boot loader */

	.org	0x21c
ramdisk_size:
	.long	0	/* Filled in by boot loader */

	.org	0x228
cmd_line_ptr:
	.long	0	/* Filled in by boot loader */

	.org	0x22c
ramdisk_max:
	.long	0xffffffff

	/* Version 2.05+ */
	.org	0x230
kernel_alignment:
	.long	0x200000	/* 2MB alignment */

	.org	0x234
relocatable_kernel:
	.byte	0

	.org	0x235
min_alignment:
	.byte	0x15		/* 2^21 = 2MB */

	/* Version 2.12+ */
	.org	0x236
xloadflags:
#if __x86_64__
	.word	( XLF_KERNEL_64 | XLF_EFI_HANDOVER_64 )
#else
	.word	0
#endif

	/* Version 2.06+ */
	.org	0x238
cmdline_size:
	.long	0x7ff		/* 2047 bytes */

	/* Version 2.07+ */
	.org	0x23c
hardware_subarch:
	.long	0

	.org	0x240
hardware_subarch_data:
	.quad	0

	/* Version 2.08+ */
	.org	0x248
payload_offset:
	.long	0

	.org	0x24c
payload_length:
	.long	0

	/* Version 2.09+ */
	.org	0x250
setup_data:
	.quad	0

	/* Version 2.10+ */
	.org	0x258
pref_address:
	.quad	LOADED_HIGH_ADDRESS

	.org	0x260
init_size:
	.long	0x1000000	/* 16MB */

	/* Version 2.11+ */
	.org	0x264
handover_offset:
#if __x86_64__
	/* GRUB adds 512 for 64-bit, so subtract it here */
	.long	( _efi_handover_raw_offset - 512 )
#else
	.long	0
#endif

version_string:
	.asciz	VERSION

	/* Setup code */
	.code16
setup:
	/* Reset %cs so that labels work */
	pushw	%ds
	pushw	$( 1f - _prefix )
	lret
1:
	/* Fix up GDT */
	xorl	%eax, %eax
	movw	%cs, %ax
	shll	$4, %eax
	addl	%eax, ( gdt - _prefix + 2 )
	addl	%eax, ( gdt - _prefix + PREFIX_CS + 2 )

	/* Switch to protected mode and jump to startup code */
	cli
	data32 lgdt ( gdt - _prefix )
	movl	%cr0, %eax
	orb	$CR0_PE, %al
	movl	%eax, %cr0
	data32 ljmp $PREFIX_CS, $( 1f - _prefix )
	.code32
1:
	/* Load data segment registers */
	movw	$PREFIX_FLAT_DS, %ax
	movw	%ax, %ds
	movw	%ax, %es
	movw	%ax, %fs
	movw	%ax, %gs
	movw	%ax, %ss

	/* Zero real-mode and protected-mode .bss sections */
	xorl	%eax, %eax
	movl	$_bss16, %edi
	movl	$_bss16_len, %ecx
	rep stosb
	movl	$_bss, %edi
	movl	$_bss_len, %ecx
	rep stosb

	/* Copy payload to runtime address */
	movl	$( LOADED_HIGH_ADDRESS + _payload_pos - SETUP_LEN ), %esi
	movl	$_payload, %edi
	movl	$_payload_len, %ecx
	cld
	rep movsb

	/* Copy parameters required by runtime */
	movl	%cs:( cmd_line_ptr - _prefix ), %eax
	movl	%eax, i386(cmdline)
	movl	%cs:( ramdisk_image - _prefix ), %eax
	movl	%eax, i386(initrd)
	movl	%cs:( ramdisk_size - _prefix ), %eax
	movl	%eax, i386(initrd_len)

	/* Jump to payload */
	ljmp	$PREFIX_FLAT_CS, $i386(startup)
	.size	setup, . - setup

	/* Global descriptor table */
gdt:
	.word	gdt_limit
	.long	( gdt - _prefix )
	/* 32-bit protected mode code segment based at real-mode %cs:0000 */
	.org	( gdt + PREFIX_CS )
	.word	0xffff, 0
	.byte	0, 0x9f, 0xcf, 0
	/* 32 bit protected mode flat code segment */
	.org	( gdt + PREFIX_FLAT_CS )
	.word	0xffff, 0
	.byte	0, 0x9f, 0xcf, 0
	/* 32 bit protected mode flat data segment */
	.org	( gdt + PREFIX_FLAT_DS )
	.word	0xffff, 0
	.byte	0, 0x93, 0xcf, 0	
	.size	gdt, . - gdt
	.equ	gdt_limit, . - gdt - 1

#endif

	.org	SETUP_LEN
