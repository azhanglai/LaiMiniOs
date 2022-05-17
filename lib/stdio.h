/*
 * @Author: azhanglai 1182585414@qq.com
 * @Date: 2022-05-16 16:18:37
 * @LastEditors: azhanglai 1182585414@qq.com
 * @LastEditTime: 2022-05-17 11:25:33
 * @FilePath: \myminiOS\lib\stdio.h
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
#ifndef __LIB_STDIO_H
#define __LIB_STDIO_H

#include "stdint.h"

typedef char* va_list;
uint32_t printf(const char* str, ...);
uint32_t vsprintf(char* str, const char* format, va_list ap);
uint32_t sprintf(char* buf, const char* format, ...);

#endif

