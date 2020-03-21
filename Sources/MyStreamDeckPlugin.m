//==============================================================================
/**
 @file       MyStreamDeckPlugin.m
 
 @brief      A Stream Deck plugin controlling Meet in Chrome with Applescript
 
 @copyright  (c) 2020, Gavin Brock.
 This source code is licensed under the MIT-style license found in the LICENSE file.
 
 **/
//==============================================================================

#import "MyStreamDeckPlugin.h"

#import "ESDSDKDefines.h"
#import "ESDConnectionManager.h"
#import "ESDUtilities.h"
#import <AppKit/AppKit.h>


// Refresh the muter states every 5s
#define CHECK_STATE_TIME		5.0



// MARK: - Utility methods


//
// Utility function to get the fullpath of an resource in the bundle
//
static NSString * GetResourcePath(NSString *inFilename)
{
    NSString *outPath = nil;
    
    if([inFilename length] > 0)
    {
        NSString * bundlePath = [ESDUtilities pluginPath];
        if(bundlePath != nil)
        {
            outPath = [bundlePath stringByAppendingPathComponent:inFilename];
        }
    }
    
    return outPath;
}

//
// Utility function to run an applescript
//
static Boolean runAppleSrcipt(NSString * script)
{
    NSDictionary *errors = nil;
    NSURL* url = [NSURL fileURLWithPath:GetResourcePath(script)];
    NSAppleScript* appleScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
    if(appleScript != nil)
    {
        [appleScript executeAndReturnError:&errors];
        return TRUE;
    }
    return FALSE;
}


// MARK: - MyStreamDeckPlugin

@interface MyStreamDeckPlugin ()

// Tells us if Chrome is running
@property (assign) BOOL isChromeRunning;

// A timer fired each minute to update the mute states
@property (strong) NSTimer *refreshTimer;

// The list of visible contexts, and theur action types
@property (strong) NSMutableDictionary *knownContexts;

@end



@implementation MyStreamDeckPlugin


// MARK: - Setup the instance variables if needed

- (void)setupIfNeeded
{
    // Create the array of known contexts
    if(_knownContexts == nil)
    {
        _knownContexts = [[NSMutableDictionary alloc] init];
    }
    
    // Create a timer to repetivily update the actions
    if(_refreshTimer == nil)
    {
        _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:CHECK_STATE_TIME target:self selector:@selector(refreshMuteStates) userInfo:nil repeats:YES];
    }
}


// MARK: - Refresh all actions

- (void)refreshMuteStates
{
    [self.connectionManager logMessage:@"Refresh"];
    
    if(!self.isChromeRunning)
    {
        return;
    }
    
    NSURL* url = [NSURL fileURLWithPath:GetResourcePath(@"applescripts/GetState.scpt")];
    NSString *voiceMute = @"false";
    NSString *videoMute = @"false";
    
    NSDictionary *errors = nil;
    NSAppleScript* appleScript = [[NSAppleScript alloc] initWithContentsOfURL:url error:&errors];
    if(appleScript != nil)
    {
        NSAppleEventDescriptor *eventDescriptor = [appleScript executeAndReturnError:&errors];
        if(eventDescriptor != nil && [eventDescriptor descriptorType] != kAENullEvent)
        {
            NSString *muteStates;
            muteStates = (NSString*)[eventDescriptor stringValue];
            if (muteStates != nil)
            {
                NSArray *listItems = [muteStates componentsSeparatedByString:@","];
                if (listItems[0] != nil) voiceMute = listItems[0];
                if (listItems[1] != nil) videoMute = listItems[1];
            }
        }
    }
    
    // Update each known context with the new value
    for (NSString* context in self.knownContexts)
    {
        NSString *action = self.knownContexts[context];
        if ([action isEqualToString:@"org.brock-family.meet.voice.action"])
        {
            if([voiceMute isEqualToString:@"true"]) [self.connectionManager setState:@0 forContext:context];
            else [self.connectionManager setState:@1 forContext:context];
        }
        else if ([action isEqualToString:@"org.brock-family.meet.video.action"])
        {
            if([videoMute isEqualToString:@"true"]) [self.connectionManager setState:@0 forContext:context];
            else [self.connectionManager setState:@1 forContext:context];
        }
    }
}


// MARK: - Events handler
// [self.connectionManager showAlertForContext:context];


- (void)keyDownForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    if ([action isEqualToString:@"org.brock-family.meet.focus.action"]) {
        runAppleSrcipt(@"applescripts/FocusMeet.scpt");
    }
    else if ([action isEqualToString:@"org.brock-family.meet.hangup.action"]) {
        runAppleSrcipt(@"applescripts/HangupMeet.scpt");
    }
    else if([action isEqualToString:@"org.brock-family.meet.ptt.action"]) {
        runAppleSrcipt(@"applescripts/VoiceUnmute.scpt");
    }
    else if ([action isEqualToString:@"org.brock-family.meet.voice.action"]) {
        runAppleSrcipt(@"applescripts/VoiceToggle.scpt");
    }
    else if ([action isEqualToString:@"org.brock-family.meet.video.action"]) {
        runAppleSrcipt(@"applescripts/VideoToggle.scpt");
    }
    [self refreshMuteStates];
    
}

- (void)keyUpForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    if([action isEqualToString:@"org.brock-family.meet.ptt.action"]) {
        runAppleSrcipt(@"applescripts/VoiceMute.scpt");
    }
    [self refreshMuteStates];
}


- (void)willAppearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    // Set up the instance variables if needed
    [self setupIfNeeded];
    
    // Add the context to the list of known contexts
    [self.knownContexts setObject:action forKey:context];
    
    // Explicitely refresh the mute state
    [self refreshMuteStates];
}

- (void)willDisappearForAction:(NSString *)action withContext:(id)context withPayload:(NSDictionary *)payload forDevice:(NSString *)deviceID
{
    // Remove the context from the list of known contexts
    [self.knownContexts removeObjectForKey:context];
}

- (void)deviceDidConnect:(NSString *)deviceID withDeviceInfo:(NSDictionary *)deviceInfo
{
    // Nothing to do
}

- (void)deviceDidDisconnect:(NSString *)deviceID
{
    // Nothing to do
}

- (void)applicationDidLaunch:(NSDictionary *)applicationInfo
{
    [self.connectionManager logMessage:@"applicationDidLaunch"];
    
    if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:@"com.google.Chrome"])
    {
        self.isChromeRunning = YES;
        // Explicitely check state
        [self refreshMuteStates];
    }
}

- (void)applicationDidTerminate:(NSDictionary *)applicationInfo
{
    [self.connectionManager logMessage:@"applicationDidTerminate"];
    if([applicationInfo[@kESDSDKPayloadApplication] isEqualToString:@"com.google.Chrome"])
    {
        self.isChromeRunning = NO;
    }
}

@end
