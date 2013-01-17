/*
 * Copyright (C) Mellanox Technologies Ltd. 2001-2012.  ALL RIGHTS RESERVED.
 *
 * This software product is a proprietary product of Mellanox Technologies Ltd.
 * (the "Company") and all right, title, and interest in and to the software product,
 * including all associated intellectual property rights, are and shall
 * remain exclusively with the Company.
 *
 * This software product is governed by the End User License Agreement
 * provided with the software product.
 *
 */

/*
 * Bullseye Coverage Definitions
*/
#ifndef BULLSEYE_H_
#define BULLSEYE_H_

#if _BullseyeCoverage
#define BULLSEYE_EXCLUDE_BLOCK_START	"BullseyeCoverage save off";
#define BULLSEYE_EXCLUDE_BLOCK_END	"BullseyeCoverage restore";
#else
#define BULLSEYE_EXCLUDE_BLOCK_START
#define BULLSEYE_EXCLUDE_BLOCK_END
#endif


#endif /* BULLSEYE_H_ */
