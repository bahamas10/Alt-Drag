//
//  AppDelegate.m
//  Alt Drag
//
//  Created by David Eddy on 7/15/14.
//  Copyright (c) 2014 David Eddy. All rights reserved.
//

#import "AppDelegate.h"

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <AppKit/AppKit.h>

enum {
    kAltDragModeNone = 0,
    kAltDragModeMove,
    kAltDragModeResize
};

@implementation AppDelegate {
    AXUIElementRef windowRef;
    CGPoint offset;
    
    int quadrant;
    int mode;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // defaults
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
                                                            @"fourCornerResizing": @NO,
                                                            }];
    
    // listen for keys
    [NSEvent addGlobalMonitorForEventsMatchingMask:NSFlagsChangedMask handler:^(NSEvent *e) {
        [self flagsChanged:e];
    }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSFlagsChangedMask handler:^(NSEvent *e) {
        [self flagsChanged:e];
        return e;
    }];
    
    // listen for mouse
    [NSEvent addGlobalMonitorForEventsMatchingMask:NSMouseMovedMask handler:^(NSEvent *e) {
        [self mouseMoved:e];
    }];
}

#pragma mark - key press events

- (void)flagsChanged:(NSEvent *)e
{
    // TODO don't hardcode hotkeys
    if (e.modifierFlags & NSShiftKeyMask && e.modifierFlags & NSAlternateKeyMask) {
        mode = kAltDragModeResize;
        NSLog(@"resize mode activated");
    } else if (e.modifierFlags & NSCommandKeyMask && e.modifierFlags & NSShiftKeyMask) {
        mode = kAltDragModeMove;
        NSLog(@"move mode activated");
    } else {
        mode = kAltDragModeNone;
        windowRef = 0;
        NSLog(@"mode none");
        return;
    }
    
    CGPoint mouse = NSEvent.mouseLocation;
    mouse.y = [self normalizeY:mouse.y];
    
    // get all windows
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    NSArray *windows = CFBridgingRelease(windowList);
    
    // loop open windows
    for (NSMutableDictionary *window in windows) {
        // only concerned with regular windows
        if ([[window objectForKey:(id)kCGWindowLayer] intValue] > 0)
            continue;
        
        // window title
        NSString *name = [window objectForKey:(id)kCGWindowName];
        
        // get the window bounds to determine if the mouse is over it
        CGRect bounds;
        CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)[window objectForKey:(id)kCGWindowBounds], &bounds);
        
        // check if the window is under the mouse
        quadrant = [self quadrantPoint:mouse inRect:bounds];
        if (quadrant == 0)
            continue;
        
        NSLog(@"tracking (quad %d): %@", quadrant, name);
        
        // get the accessibility window reference
        pid_t pid = [[window objectForKey:(id)kCGWindowOwnerPID] intValue];
        AXUIElementRef appRef = AXUIElementCreateApplication(pid);
        CFArrayRef windowList;
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute, (CFTypeRef *)&windowList);
        
        // get just the first window for now (???)
        windowRef = (AXUIElementRef)CFArrayGetValueAtIndex(windowList, 0);
        
        // save the original window location
        offset = CGPointMake(mouse.x - bounds.origin.x, mouse.y - bounds.origin.y);
        
        // bring the window to the front
        /*
        AXUIElementSetAttributeValue(windowRef, kAXMainAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue(windowRef, kAXFocusedApplicationAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue(windowRef, kAXFocusedAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue(windowRef, kAXFocusedWindowAttribute, kCFBooleanTrue);
        AXUIElementSetAttributeValue(windowRef, kAXFrontmostAttribute, kCFBooleanTrue);
         */
        /*
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        NSLog(@"%@", app);
        [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
         */
        
        break;
    }
}

- (void)mouseMoved:(NSEvent *)e
{
    if (mode == kAltDragModeNone)
        return;
    
    CGPoint mouse = NSEvent.mouseLocation;
    
    CFTypeRef temp;
    
    CGPoint windowLocation = NSMakePoint(mouse.x, mouse.y);
    windowLocation.y = [self normalizeY:windowLocation.y];
    
    CGSize windowSize;
    
    switch (mode) {
        case kAltDragModeMove:
            windowLocation.x -= offset.x;
            windowLocation.y -= offset.y;
            
            temp = (CFTypeRef)(AXValueCreate(kAXValueCGPointType, (const void *)&windowLocation));
            AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute, temp);
            break;
        case kAltDragModeResize:
            AXUIElementCopyAttributeValue(windowRef, kAXSizeAttribute, &temp);
            AXValueGetValue(temp, kAXValueCGSizeType, &windowSize);
            AXUIElementCopyAttributeValue(windowRef, kAXPositionAttribute, &temp);
            AXValueGetValue(temp, kAXValueCGPointType, &windowLocation);
            
            if ([NSUserDefaults.standardUserDefaults boolForKey:@"fourCornerResizing"]) {
                switch (quadrant) {
                    case 1:
                        windowSize.width += e.deltaX;
                        windowSize.height -= e.deltaY;
                        windowLocation.y += e.deltaY;
                        break;
                    case 2:
                        windowSize.width -= e.deltaX;
                        windowLocation.x += e.deltaX;
                        windowSize.height -= e.deltaY;
                        windowLocation.y += e.deltaY;
                        break;
                    case 3:
                        windowSize.width -= e.deltaX;
                        windowLocation.x += e.deltaX;
                        windowSize.height += e.deltaY;
                        break;
                    case 4:
                        windowSize.height += e.deltaY;
                        windowSize.width += e.deltaX;
                        break;
                }
            } else {
                windowSize.height += e.deltaY;
                windowSize.width += e.deltaX;
                
            }
            
            temp = (CFTypeRef)(AXValueCreate(kAXValueCGSizeType, (const void *)&windowSize));
            AXUIElementSetAttributeValue(windowRef, kAXSizeAttribute, temp);
            temp = (CFTypeRef)(AXValueCreate(kAXValueCGPointType, (const void *)&windowLocation));
            AXUIElementSetAttributeValue(windowRef, kAXPositionAttribute, temp);
            
            break;
        default:
            return;
    }
    
    CFRelease(temp);
}

#pragma mark - CGRect Helpers
- (int)quadrantPoint:(CGPoint)point inRect:(CGRect)rect
{
    if (!NSPointInRect(point, rect))
        return 0;
    
    BOOL isWest = point.x <= NSMidX(rect);
    BOOL isSouth = point.y >= NSMidY(rect);
    
    if (!isWest && !isSouth)
        return 1;
    else if (isWest && !isSouth)
        return 2;
    else if (isWest && isSouth)
        return 3;
    else if (!isWest && isSouth)
        return 4;
    return 0;
}

// TODO handle multiple monitors
- (float)normalizeY:(float)y
{
    return NSScreen.mainScreen.frame.size.height - y;
}

@end