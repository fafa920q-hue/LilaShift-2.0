// SPDX-License-Identifier: GPL-3.0-only
#import "GXMobileGestaltImage.h"
#import <TargetConditionals.h>
#import <ctype.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <string.h>

static NSData *GXCopySection(const struct mach_header_64 *header, intptr_t slide,
                             const char *segment, const char *name, uint64_t *address) {
    const struct section_64 *section = getsectbynamefromheader_64(header, segment, name);
    if (!section || !section->size || section->size > 32 * 1024 * 1024) return nil;
    uintptr_t start = (uintptr_t)section->addr + (uintptr_t)slide;
    if (!start || start + section->size < start) return nil;
    if (address) *address = start;
    return [NSData dataWithBytes:(const void *)start length:(NSUInteger)section->size];
}

NSDictionary<NSString *, id> *GXCopyMobileGestaltImage(void) {
#if TARGET_OS_SIMULATOR
    return nil;
#else
    static NSDictionary *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *path = "/usr/lib/libMobileGestalt.dylib";
        // Keep the library loaded. No query hooks, library writes or device writes.
        if (!dlopen(path, RTLD_LAZY | RTLD_LOCAL)) return;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name || strcmp(name, path)) continue;
            const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
            if (!header || header->magic != MH_MAGIC_64) return;
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            uint64_t stringAddress = 0;
            NSData *strings = GXCopySection(header, slide, "__TEXT", "__cstring", &stringAddress);
            NSMutableArray<NSData *> *constants = [NSMutableArray array];
            const char *segments[] = {"__AUTH_CONST", "__DATA_CONST", "__DATA"};
            for (size_t j = 0; j < sizeof(segments) / sizeof(segments[0]); j++) {
                NSData *data = GXCopySection(header, slide, segments[j], "__const", NULL);
                if (data) [constants addObject:data];
            }
            // UUID strings harvested from `__cfstring`: a second source for
            // the CacheUUID if a future iOS moves it out of `__cstring`.
            // Adapted from Erosion-CN's MGImageReader `__cfstring` walk;
            // simplified for GestaltX: 32-byte entries are accepted only
            // when their length is 36 and their data pointer lands inside
            // the copied `__cstring` range, and only UUID-shaped text is
            // kept. No pointer outside that range is ever read.
            NSMutableArray<NSString *> *cfUUIDs = [NSMutableArray array];
            if (strings && stringAddress != 0) {
                const char *cfSegments[] = {"__AUTH_CONST", "__DATA_CONST"};
                for (size_t j = 0; j < sizeof(cfSegments) / sizeof(cfSegments[0]); j++) {
                    unsigned long cfSize = 0;
                    const uint8_t *cfPtr = getsectiondata(header, cfSegments[j], "__cfstring", &cfSize);
                    if (!cfPtr || cfSize < 32 || cfSize > 8 * 1024 * 1024) continue;
                    for (size_t off = 0; off + 32 <= cfSize; off += 32) {
                        uint64_t rawDataPtr = 0, rawLen = 0;
                        memcpy(&rawDataPtr, cfPtr + off + 16, sizeof(uint64_t));
                        memcpy(&rawLen, cfPtr + off + 24, sizeof(uint64_t));
                        if (rawLen != 36) continue;
                        uint64_t charPtr = rawDataPtr & 0x00007FFFFFFFFFFFULL;
                        if (charPtr < stringAddress || charPtr + 36 > stringAddress + strings.length) continue;
                        const char *chars = (const char *)(uintptr_t)charPtr;
                        BOOL isUUID = YES;
                        for (int c = 0; c < 36; c++) {
                            unsigned char ch = (unsigned char)chars[c];
                            if (c == 8 || c == 13 || c == 18 || c == 23) {
                                if (ch != '-') { isUUID = NO; break; }
                            } else if (!isxdigit(ch)) { isUUID = NO; break; }
                        }
                        if (!isUUID) continue;
                        NSString *candidate = [[NSString alloc] initWithBytes:chars length:36 encoding:NSASCIIStringEncoding];
                        if (candidate && [[NSUUID alloc] initWithUUIDString:candidate] != nil) {
                            [cfUUIDs addObject:candidate];
                        }
                    }
                }
            }
            if (strings && constants.count) {
                image = @{ @"strings": strings, @"stringAddress": @(stringAddress), @"constants": constants, @"cfUUIDs": [cfUUIDs copy] };
            }
            return;
        }
    });
    return image;
#endif
}
