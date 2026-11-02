// Shared between the tweak (SpringBoard) and the settings bundle.
#define PODomain @"com.pulloverpro.ios26"
#define POStateDomain @"com.pulloverpro.ios26.state"   // handle position, last pinned app
#define POPrefsChangedNotification "com.pulloverpro.ios26/changed"
// Commands other tweaks can post (Darwin notifications):
// pull the pinned app over, close it, or switch between the two.
#define POOpenNotification "com.pulloverpro.ios26/open"
#define POCloseNotification "com.pulloverpro.ios26/close"
#define POToggleNotification "com.pulloverpro.ios26/toggle"
