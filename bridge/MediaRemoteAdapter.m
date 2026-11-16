// MediaRemoteAdapter: reads the system "Now Playing" info (any app: browsers, YouTube,
// Music, Spotify, podcasts...) and sends media commands.
//
// Since macOS 15.4, MediaRemote only answers Apple-signed processes, so this dylib is
// loaded into /usr/bin/perl by mr-bridge.pl. Protocol:
//   stdout: one JSON object per line whenever now-playing state changes
//   stdin:  commands, one per line: play | pause | toggle | next | previous | seek <seconds>
//           | pauseapp <bundle id> | refresh
// The process exits when stdin closes (i.e. when Dynamic Island quits).

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientStringFn)(id);
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);
typedef void *(*LocalOriginFn)(void);
typedef Boolean (*SendToAppFn)(int, CFDictionaryRef, void *, CFStringRef, unsigned int,
                               dispatch_queue_t, void (^)(unsigned int, CFArrayRef));

static RegisterFn MRRegister;
static GetInfoFn MRGetInfo;
static GetPlayingFn MRGetPlaying;
static GetClientFn MRGetClient;
static ClientStringFn MRClientBundle;
static ClientStringFn MRClientParentBundle;
static SendCommandFn MRSendCommand;
static SetElapsedFn MRSetElapsed;
static LocalOriginFn MRLocalOrigin;
static SendToAppFn MRSendToApp;
static void *mrHandle;

static dispatch_queue_t mrQueue;
static NSString *lastLine;
static NSData *lastArtwork;
static unsigned long long artworkSerial;

static BOOL loadMediaRemote(void) {
    mrHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mrHandle) return NO;
    MRRegister = (RegisterFn)dlsym(mrHandle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    MRGetInfo = (GetInfoFn)dlsym(mrHandle, "MRMediaRemoteGetNowPlayingInfo");
    MRGetPlaying = (GetPlayingFn)dlsym(mrHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    MRGetClient = (GetClientFn)dlsym(mrHandle, "MRMediaRemoteGetNowPlayingClient");
    MRClientBundle = (ClientStringFn)dlsym(mrHandle, "MRNowPlayingClientGetBundleIdentifier");
    MRClientParentBundle = (ClientStringFn)dlsym(mrHandle, "MRNowPlayingClientGetParentAppBundleIdentifier");
    MRSendCommand = (SendCommandFn)dlsym(mrHandle, "MRMediaRemoteSendCommand");
    MRSetElapsed = (SetElapsedFn)dlsym(mrHandle, "MRMediaRemoteSetElapsedTime");
    MRLocalOrigin = (LocalOriginFn)dlsym(mrHandle, "MRMediaRemoteGetLocalOrigin");
    MRSendToApp = (SendToAppFn)dlsym(mrHandle, "MRMediaRemoteSendCommandToApp");
    return MRRegister && MRGetInfo && MRGetPlaying && MRSendCommand;
}

static void emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    if ([line isEqualToString:lastLine]) return;
    lastLine = line;
    fprintf(stdout, "%s\n", line.UTF8String);
    fflush(stdout);
}

static id stringOrEmpty(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static id numberOrZero(id value) {
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

static void publish(NSDictionary *info, BOOL playing, NSString *bundle, NSString *parent) {
    NSString *title = stringOrEmpty(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
    if (info.count == 0 || title.length == 0) {
        lastArtwork = nil;
        emit(@{ @"empty": @YES });
        return;
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"title"] = title;
    out[@"artist"] = stringOrEmpty(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    out[@"album"] = stringOrEmpty(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
    out[@"duration"] = numberOrZero(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
    out[@"elapsed"] = numberOrZero(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
    out[@"rate"] = numberOrZero(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
    id ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    out[@"timestamp"] = @([ts isKindOfClass:[NSDate class]] ? [ts timeIntervalSince1970]
                                                             : [NSDate date].timeIntervalSince1970);
    out[@"playing"] = @(playing);
    out[@"explicit"] = @([numberOrZero(info[@"kMRMediaRemoteNowPlayingInfoIsExplicitTrack"]) boolValue]);
    out[@"bundle"] = bundle ?: @"";
    out[@"parent"] = parent ?: @"";
    id uid = info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]
          ?: info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"];
    out[@"id"] = uid ? [uid description] : @"";

    id art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([art isKindOfClass:[NSData class]] && [art length] > 0) {
        // A counter, not -[NSData hash]: that only looks at the first bytes, which are
        // identical for most JPEGs, so different covers would collide.
        if (![art isEqualToData:lastArtwork]) {
            lastArtwork = art;
            artworkSerial += 1;
            out[@"artwork"] = [art base64EncodedStringWithOptions:0];
        }
        out[@"artworkHash"] = @(artworkSerial);
    } else {
        lastArtwork = nil;
        out[@"artworkHash"] = @0;
    }
    emit(out);
}

static void update(void) {
    MRGetInfo(mrQueue, ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = cfInfo ? [(__bridge NSDictionary *)cfInfo copy] : @{};
        MRGetPlaying(mrQueue, ^(Boolean playing) {
            if (MRGetClient && MRClientBundle) {
                MRGetClient(mrQueue, ^(id client) {
                    NSString *bundle = client ? (__bridge NSString *)MRClientBundle(client) : nil;
                    NSString *parent = (client && MRClientParentBundle)
                        ? (__bridge NSString *)MRClientParentBundle(client) : nil;
                    publish(info, playing, bundle, parent);
                });
            } else {
                publish(info, playing, nil, nil);
            }
        });
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;
    if ([cmd isEqualToString:@"play"]) MRSendCommand(0, NULL);
    else if ([cmd isEqualToString:@"pause"]) MRSendCommand(1, NULL);
    else if ([cmd isEqualToString:@"toggle"]) MRSendCommand(2, NULL);
    else if ([cmd isEqualToString:@"next"]) MRSendCommand(4, NULL);
    else if ([cmd isEqualToString:@"previous"]) MRSendCommand(5, NULL);
    else if ([cmd isEqualToString:@"seek"] && parts.count > 1 && MRSetElapsed) MRSetElapsed(parts[1].doubleValue);
    else if ([cmd isEqualToString:@"pauseapp"] && parts.count > 1 && MRSendToApp && MRLocalOrigin) {
        // Pause one specific app (not whichever is "now playing").
        MRSendToApp(1, NULL, MRLocalOrigin(), (__bridge CFStringRef)parts[1], 0, mrQueue,
                    ^(unsigned int error, CFArrayRef statuses) {});
    }
    else if ([cmd isEqualToString:@"refresh"]) dispatch_async(mrQueue, ^{ lastLine = nil; update(); });
}

__attribute__((visibility("default")))
void adapter_run(void) {
    @autoreleasepool {
        if (!loadMediaRemote()) {
            emit(@{ @"error": @"MediaRemote unavailable" });
            exit(1);
        }
        mrQueue = dispatch_queue_create("dynamicisland.mediaremote", DISPATCH_QUEUE_SERIAL);
        MRRegister(mrQueue);

        NSArray *names = @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                            @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange" ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *note) {
                dispatch_async(mrQueue, ^{ update(); });
            }];
        }

        // Commands on stdin; exit when the app closes the pipe.
        dispatch_source_t input = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0,
                                                         dispatch_get_main_queue());
        __block NSMutableString *buffer = [NSMutableString string];
        dispatch_source_set_event_handler(input, ^{
            char chunk[1024];
            ssize_t n = read(STDIN_FILENO, chunk, sizeof(chunk));
            if (n <= 0) exit(0);
            [buffer appendString:[[NSString alloc] initWithBytes:chunk length:n encoding:NSUTF8StringEncoding] ?: @""];
            NSRange nl;
            while ((nl = [buffer rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [buffer substringToIndex:nl.location];
                [buffer deleteCharactersInRange:NSMakeRange(0, nl.location + 1)];
                handleCommand([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]);
            }
        });
        dispatch_resume(input);

        // Safety net: re-read every few seconds, and quit if our parent is gone.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, mrQueue);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 3 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(timer, ^{
            if (getppid() == 1) exit(0);
            update();
        });
        dispatch_resume(timer);

        CFRunLoopRun();
    }
}
