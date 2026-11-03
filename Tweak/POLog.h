// Debug builds log each step to a file. SpringBoard's sandbox refuses writes to
// /var/tmp on newer iOS versions, so try its own writable folders first.
// Release builds: no-op.
#import <Foundation/Foundation.h>
#if DEBUG
static inline NSString *POLogFilePath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *candidates = @[
            @"/var/mobile/Library/SpringBoard/pulloverpro.log",
            @"/var/mobile/Library/Caches/com.apple.springboard/pulloverpro.log",
            @"/var/mobile/Library/Logs/pulloverpro.log",
            @"/var/tmp/pulloverpro.log",
        ];
        for (NSString *candidate in candidates) {
            NSString *dir = [candidate stringByDeletingLastPathComponent];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            if ([fm createFileAtPath:candidate contents:nil attributes:nil]) {
                path = candidate;
                break;
            }
            if ([fm isWritableFileAtPath:candidate]) {
                path = candidate;
                break;
            }
        }
        path = path ?: candidates.lastObject;
    });
    return path;
}

static inline void POLogLine(NSString *line) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("pulloverpro.log", DISPATCH_QUEUE_SERIAL); });
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    dispatch_async(q, ^{
        NSString *path = POLogFilePath();
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [stamped writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; return; }
        [h seekToEndOfFile];
        [h writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    });
}
#define POLog(fmt, ...) POLogLine([NSString stringWithFormat:fmt, ##__VA_ARGS__])
#else
#define POLog(fmt, ...) do {} while (0)
#endif
