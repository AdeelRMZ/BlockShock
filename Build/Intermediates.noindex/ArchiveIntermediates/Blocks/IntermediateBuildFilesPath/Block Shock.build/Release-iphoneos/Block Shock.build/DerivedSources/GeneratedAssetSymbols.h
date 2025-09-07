#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.block.shock";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "blast" asset catalog image resource.
static NSString * const ACImageNameBlast AC_SWIFT_PRIVATE = @"blast";

/// The "homeIcon" asset catalog image resource.
static NSString * const ACImageNameHomeIcon AC_SWIFT_PRIVATE = @"homeIcon";

/// The "rotate" asset catalog image resource.
static NSString * const ACImageNameRotate AC_SWIFT_PRIVATE = @"rotate";

/// The "settingsIcon" asset catalog image resource.
static NSString * const ACImageNameSettingsIcon AC_SWIFT_PRIVATE = @"settingsIcon";

/// The "tetris" asset catalog image resource.
static NSString * const ACImageNameTetris AC_SWIFT_PRIVATE = @"tetris";

/// The "trophy2d" asset catalog image resource.
static NSString * const ACImageNameTrophy2D AC_SWIFT_PRIVATE = @"trophy2d";

#undef AC_SWIFT_PRIVATE
