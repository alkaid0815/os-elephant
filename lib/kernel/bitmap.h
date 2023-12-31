#ifndef __LIB_KERNEL_BITMAP_H
#define __LIB_KERNEL_BITMAP_H

#include "global.h"
#define BITMAP_MASK 1

typedef struct {
	uint32_t btmp_bytes_len;
	uint8_t *bits;
} bitmap;

void bitmap_init(bitmap *btmp);
bool bitmap_scan_test(bitmap *btmp, uint32_t bit_idx);
int bitmap_scan(bitmap *btmp, uint32_t cnt);
void bitmap_set(bitmap *btmp, uint32_t bit_idx, int8_t value);

#endif