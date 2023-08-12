#include "bitmap.h"
#include "stdint.h"
#include "string.h"
#include "interrupt.h"
#include "debug.h"

/* 将位图btmp初始化 */
void bitmap_init(bitmap *btmp) {
	memset(btmp->bits, 0, btmp->btmp_bytes_len);
}

/* 判断bit_idx位是否为1,若为1,则返回true,否则返回false */
bool bitmap_scan_test(struct bitmap *btmp, uint32_t bit_idx) {
	ASSERT(bit_idx / 8 < btmp->btmp_bytes_len);
	return btmp->bits[bit_idx / 8] & (BITMAP_MASK << (bit_idx % 8));
}

/* 在位图中申请连续cnt个位,成功,则返回其起始位下标,失败,返回−1 */
int bitmap_scan(struct bitmap *btmp, uint32_t cnt) {
	uint32_t idx_byte = 0; 						// 用于记录空闲位所在的字节
	while (idx_byte < btmp->btmp_bytes_len && 0xff == btmp->bits[idx_byte]) {
		++idx_byte;
	}

	if (idx_byte == btmp->btmp_bytes_len) return -1;

	uint32_t idx_bit = idx_byte * 8;
	uint32_t count = 0;
	uint32_t bit_left = (btmp->btmp_bytes_len * 8 - idx_bit);
	while (bit_left--) {
		if (!bitmap_scan_test(btmp, idx_bit++)) ++count;
		else count = 0;

		if (count == cnt) return idx_bit - cnt;
	}

	return -1;
}

/* 将位图btmp的bit_idx位设置为value */
void bitmap_set(struct bitmap *btmp, uint32_t bit_idx, int8_t value) {
	ASSERT((value == 0) || (value == 1));
	if (value) {
		bits[bit_idx / 8] |= (BITMAP_MASK << (bit_idx % 8));
	} else {
		bits[bit_idx / 8] &= ~(BITMAP_MASK << (bit_idx % 8));
	}
}


