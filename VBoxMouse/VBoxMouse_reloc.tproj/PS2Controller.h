/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
#import <driverkit/IODirectDevice.h>

typedef struct {
	void	(*_sendControllerCommand)(char cmd);
	char	(*_getKeyboardData)(void);
	BOOL	(*_getKeyboardDataIfPresent)(char *data);
	void	(*_clearOutputBuffer)(void);
	void	(*_sendControllerData)(char data);
	void	(*_sendMouseCommand)(char cmd);
	char	(*_getMouseData)(void);
	BOOL	(*_getMouseDataIfPresent)(char *data);
} t_ps2_funcs;


@interface PS2Controller : IODirectDevice
{
}

- (t_ps2_funcs*)controllerAccessFunctions;

- (void)setManualDataHandling:(BOOL)flag;
- (void)setMouseObject:aMouseDevice;

@end