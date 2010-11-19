//
//  ORMMAJavascriptBridge.m
//  RichMediaAds
//
//  Created by Robert Hedin on 9/7/10.
//  Copyright 2010 The Weather Channel. All rights reserved.
//

#import <MessageUI/MessageUI.h>
#import "ORMMAJavascriptBridge.h"
#import "Reachability.h"
#import "UIColor-Expanded.h"
#import "UIDevice-ORMMA.h"



@interface ORMMAJavascriptBridge ()

@property( nonatomic, retain ) Reachability *reachability;

- (NSDictionary *)parametersFromJSCall:(NSString *)parameterString;
- (BOOL)processCommand:(NSString *)command
			parameters:(NSDictionary *)parameters
			forWebView:(UIWebView *)webView;
- (BOOL)processCloseCommand:(NSDictionary *)parameters
				 forWebView:(UIWebView *)webView;
- (BOOL)processExpandCommand:(NSDictionary *)parameters
				  forWebView:(UIWebView *)webView;
- (BOOL)processHideCommand:(NSDictionary *)parameters
				forWebView:(UIWebView *)webView;
- (BOOL)processResizeCommand:(NSDictionary *)parameters
				  forWebView:(UIWebView *)webView;
- (BOOL)processServiceCommand:(NSDictionary *)parameters
				   forWebView:(UIWebView *)webView;
- (BOOL)processShowCommand:(NSDictionary *)parameters
				forWebView:(UIWebView *)webView;
- (BOOL)processOpenCommand:(NSDictionary *)parameters
				forWebView:(UIWebView *)webView;
- (BOOL)processRequestCommand:(NSDictionary *)parameters
				   forWebView:(UIWebView *)webView;
- (BOOL)processCalendarCommand:(NSDictionary *)parameters
					forWebView:(UIWebView *)webView;
- (BOOL)processCameraCommand:(NSDictionary *)parameters
				  forWebView:(UIWebView *)webView;
- (BOOL)processEMailCommand:(NSDictionary *)parameters
				 forWebView:(UIWebView *)webView;
- (BOOL)processPhoneCommand:(NSDictionary *)parameters
				 forWebView:(UIWebView *)webView;
- (BOOL)processSMSCommand:(NSDictionary *)parameters
			   forWebView:(UIWebView *)webView;
- (BOOL)processAddAssetCommand:(NSDictionary *)parameters
					forWebView:(UIWebView *)webView;
- (BOOL)processRemoveAssetCommand:(NSDictionary *)parameters
					   forWebView:(UIWebView *)webView;
- (BOOL)processRemoveAllAssetsCommand:(NSDictionary *)parameters
						   forWebView:(UIWebView *)webView;

- (CGFloat)floatFromDictionary:(NSDictionary *)dictionary
						forKey:(NSString *)key;
- (CGFloat)floatFromDictionary:(NSDictionary *)dictionary
						forKey:(NSString *)key
				   withDefault:(CGFloat)defaultValue; 
- (NSString *)requiredStringFromDictionary:(NSDictionary *)dictionary
									forKey:(NSString *)key;
- (BOOL)booleanFromDictionary:(NSDictionary *)dictionary
					   forKey:(NSString *)key;

@end




@implementation ORMMAJavascriptBridge


#pragma mark -
#pragma mark Constants

// the protocol to use to identify the ORMMA request
NSString * const ORMMAProtocol = @"ormma://";

NSString * const ORMMACommandShow = @"show";
NSString * const ORMMACommandHide = @"hide";
NSString * const ORMMACommandClose = @"close";

NSString * const ORMMACommandExpand = @"expand";
NSString * const ORMMACommandResize = @"resize";

NSString * const ORMMACommandAddAsset = @"addasset";
NSString * const ORMMACommandRemoveAsset = @"removeasset";
NSString * const ORMMACommandRemoveAllAssets = @"removeallassets";

NSString * const ORMMACommandCalendar = @"calendar";
NSString * const ORMMACommandCamera = @"camera";
NSString * const ORMMACommandEMail = @"email";
NSString * const ORMMACommandPhone = @"phone";
NSString * const ORMMACommandSMS = @"sms";

NSString * const ORMMACommandOpen = @"open";
NSString * const ORMMACommandRequest = @"request";

NSString * const ORMMACommandService = @"service";

const CGFloat kDefaultShakeIntensity = 1.5;




#pragma mark -
#pragma mark Properties

@synthesize bridgeDelegate = m_bridgeDelegate;
@synthesize reachability = m_reachability;
@synthesize motionManager = m_motionManager;
@dynamic networkStatus;



#pragma mark -
#pragma mark Initializers / Memory Management

- (ORMMAJavascriptBridge *)init
{
	if ( ( self = [super init] ) )
	{
		// set ourselves up for location based services
		m_locationManager = [[CLLocationManager alloc] init];
        m_locationManager.delegate = self;
		m_locationManager.desiredAccuracy = kCLLocationAccuracyBest;
		
		// set the default shake intensity
		m_shakeIntensity = kDefaultShakeIntensity;
		
		// check for the availability of Core Motion
		if ( NSClassFromString( @"CMMotionManager" ) != nil )
		{
			self.motionManager = [[CMMotionManager alloc] init];
		}

		// make sure to register for the events that we care about
		NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
		[notificationCenter addObserver:self
							   selector:@selector(orientationChanged:)
								   name:UIDeviceOrientationDidChangeNotification
								 object:nil];
		[notificationCenter addObserver:self
							   selector:@selector(reachabilityStateChanged:)
								   name:kReachabilityChangedNotification
								 object:nil];
		[notificationCenter addObserver:self 
							   selector:@selector(keyboardWillShow:) 
								   name:UIKeyboardWillShowNotification
								 object:nil];
		[notificationCenter addObserver:self 
							   selector:@selector(keyboardWillHide:) 
								   name:UIKeyboardWillHideNotification
								 object:nil];	}
	return self;
}


- (void)dealloc
{
	// stop listening for notifications
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	[notificationCenter removeObserver:self];
	
	[self restoreServicesToDefaultState];
	
	[m_timer invalidate], m_timer = nil;
	m_bridgeDelegate = nil;
	m_accelerometer.delegate = nil,[m_accelerometer release], m_accelerometer = nil;
	[m_locationManager release], m_locationManager = nil;
	[self.motionManager stopGyroUpdates], self.motionManager = nil;
	[super dealloc];
}



#pragma mark -
#pragma mark Dynamic Properties

- (NSString *)networkStatus
{
	NetworkStatus ns = [self.reachability currentReachabilityStatus];
	switch ( ns )
	{
		case NotReachable:
			return @"offline";
		case ReachableViaWWAN:
			return @"cell";
		case ReachableViaWiFi:
			return @"wifi";
		default:
			return @"unknown";
	}
}


#pragma mark -
#pragma mark Process

- (BOOL)processURL:(NSURL *)url
		forWebView:(UIWebView *)webView
{
	NSString *workingUrl = [url absoluteString];
	if ( [workingUrl hasPrefix:ORMMAProtocol] )
	{
		// the URL is intended for the bridge, so process it
		NSString *workingCall = [workingUrl substringFromIndex:ORMMAProtocol.length];
		
		// get the command
		NSRange r = [workingCall rangeOfString:@"?"];
		if ( r.location == NSNotFound )
		{
			// just a command
			return [self processCommand:workingCall 
							 parameters:nil
							 forWebView:webView];
		}
		NSString *command = [[workingCall substringToIndex:r.location] lowercaseString];
		NSString *parameterValues = [workingCall substringFromIndex:( r.location + 1 )];
		NSDictionary *parameters = [self parametersFromJSCall:parameterValues];
		NSLog( @"ORMMA Command: %@, %@", command, parameters );
		
		// let the callee know
		return [self processCommand:command 
						 parameters:parameters
						 forWebView:webView];
	}
	
	// not intended for the bridge
	return NO;
}


- (NSDictionary *)parametersFromJSCall:(NSString *)parameterString
{
	NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
	
	// find the start of our parameters
	NSArray *parameterList = [parameterString componentsSeparatedByString:@"&"];
	for ( NSString *parameterEntry in parameterList )
	{
		NSArray *kvp = [parameterEntry componentsSeparatedByString:@"="];
		NSString *key = [kvp objectAtIndex:0];
		NSString *encodedValue = [kvp objectAtIndex:1];
		NSString *value = [encodedValue stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];;
		[parameters setObject:value forKey:key];
	}
	
	return parameters;
}


- (BOOL)processCommand:(NSString *)command
			parameters:(NSDictionary *)parameters
			forWebView:(UIWebView *)webView
{
	BOOL processed = NO;
	if ( [command isEqualToString:ORMMACommandClose] )
	{
		// process close
		processed = [self processCloseCommand:parameters
								   forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandExpand] )
	{
		// process hide
		processed = [self processExpandCommand:parameters
									forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandHide] )
	{
		// process hide
		processed = [self processHideCommand:parameters
							 forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandResize] )
	{
		// process resize
		processed = [self processResizeCommand:parameters
							   forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandService] )
	{
		// process service
		processed = [self processServiceCommand:parameters
								forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandShow] )
	{
		// process show
		processed = [self processShowCommand:parameters
								  forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandAddAsset] )
	{
		// process show
		processed = [self processAddAssetCommand:parameters
									  forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandRemoveAsset] )
	{
		// process show
		processed = [self processRemoveAssetCommand:parameters
										 forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandRemoveAllAssets] )
	{
		// process show
		processed = [self processRemoveAllAssetsCommand:parameters
											 forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandOpen] )
	{
		// process show
		processed = [self processOpenCommand:parameters
								  forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandRequest] )
	{
		// process show
		processed = [self processRequestCommand:parameters
									 forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandCalendar] )
	{
		// process show
		processed = [self processCalendarCommand:parameters
									  forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandCamera] )
	{
		// process show
		processed = [self processCameraCommand:parameters
									forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandEMail] )
	{
		// process show
		processed = [self processEMailCommand:parameters
								   forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandPhone] )
	{
		// process show
		processed = [self processPhoneCommand:parameters
								   forWebView:webView];
	}
	else if ( [command isEqualToString:ORMMACommandSMS] )
	{
		// process show
		processed = [self processSMSCommand:parameters
								 forWebView:webView];
	}
	
	if ( !processed ) 
	{
		NSLog( @"Unknown Command: %@", command );
	}

	// notify JS that we've completed the last request
	[self.bridgeDelegate usingWebView:webView
					executeJavascript:@"window.ormmaview.nativeCallComplete( '%@' );", command];

	return processed;
}


- (BOOL)processShowCommand:(NSDictionary *)parameters
				forWebView:(UIWebView *)webView
{
	NSLog( @"Processing SHOW Command..." );
	[self.bridgeDelegate showAd:webView];
	return YES;
}


- (BOOL)processHideCommand:(NSDictionary *)parameters
				forWebView:(UIWebView *)webView
{
	NSLog( @"Processing HIDE Command..." );
	[self.bridgeDelegate hideAd:webView];
	return YES;
}


- (BOOL)processCloseCommand:(NSDictionary *)parameters
				 forWebView:(UIWebView *)webView
{
	NSLog( @"Processing CLOSE Command..." );
	[self.bridgeDelegate closeAd:webView];
	return YES;
}


- (BOOL)processExpandCommand:(NSDictionary *)parameters
				  forWebView:(UIWebView *)webView
{
	NSLog( @"Processing EXPAND Command..." );
	
	// account for status bar, if needed
	CGFloat yDelta = 0;
	UIApplication *app = [UIApplication sharedApplication];
	if ( !app.statusBarHidden )
	{
		yDelta = app.statusBarFrame.size.height;
	}
	
	// ok, to make it easy on the client, we don't require them to give us all
	// the values all the time.
	// basicallly we're going to take the current real frame information from
	// the ad (translated to window space coordinates) and set the final frame
	// to this information. Then for each data point we receive from the client,
	// we override the appropriate value. this allows the client to say things
	// like "using the current ad position, expand the ad's height to 300px"
	CGRect f = [self.bridgeDelegate getAdFrameInWindowCoordinates];
	CGFloat x = f.origin.x;
	CGFloat y = f.origin.y;
	CGFloat w = f.size.width;
	CGFloat h = f.size.height;
	
	// now get the sizes as specified by the creative
	x = [self floatFromDictionary:parameters
						   forKey:@"x"
					  withDefault:x];
	y = [self floatFromDictionary:parameters
						   forKey:@"y"
					  withDefault:y];
	w = [self floatFromDictionary:parameters
						   forKey:@"w"
					  withDefault:w];
	h = [self floatFromDictionary:parameters
						   forKey:@"h"
					  withDefault:h];
	
	BOOL useBG = [self booleanFromDictionary:parameters
									  forKey:@"useBG"];
	UIColor *blockerColor = [UIColor blackColor];
	CGFloat bgOpacity = 0.20;
	if ( useBG )
	{
		NSString *value = [parameters objectForKey:@"bgColor"];
		if ( value != nil ) 
		{
			value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ( value.length > 0 )
			{
				// we have what "should" be a color
				if ( [value hasPrefix:@"#"] ) 
				{
					// hex color
					blockerColor = [UIColor colorWithName:[value substringFromIndex:1]];
				}
				else
				{
					// assume it's a named color
					blockerColor = [UIColor colorWithName:value];
				}
			}
		}
		bgOpacity = [self floatFromDictionary:parameters
									   forKey:@"bgOpacity"
								  withDefault:1.0];
	}
	
	NSString *urlString = [parameters valueForKey:@"url"];
	NSURL *url = [NSURL URLWithString:urlString];
	NSLog( @"Expanding to ( %f, %f ) ( %f x %f ) showing %@", x, y, w, h, url );
	CGRect newFrame = CGRectMake( x, ( y + yDelta ), w, h );
	[self.bridgeDelegate expandTo:newFrame
						  withURL:url
						inWebView:webView
					blockingColor:blockerColor
				  blockingOpacity:bgOpacity];
	return YES;
}


- (BOOL)processResizeCommand:(NSDictionary *)parameters
				  forWebView:(UIWebView *)webView
{
	NSLog( @"Processing RESIZE Command..." );
	
	// get the new bounds
	CGFloat w = [self floatFromDictionary:parameters
								   forKey:@"w"];
	CGFloat h = [self floatFromDictionary:parameters
								   forKey:@"h"];
	[self.bridgeDelegate resizeToWidth:w
								height:h
							 inWebView:webView];
	return YES;
}


- (BOOL)processAddAssetCommand:(NSDictionary *)parameters
					forWebView:(UIWebView *)webView
{
	NSLog( @"Processing ADD ASSET Command..." );
	return YES;
}


- (BOOL)processRemoveAssetCommand:(NSDictionary *)parameters
					   forWebView:(UIWebView *)webView
{
	NSLog( @"Processing REMOVE ASSET Command..." );
	return YES;
}


- (BOOL)processRemoveAllAssetsCommand:(NSDictionary *)parameters
						   forWebView:(UIWebView *)webView
{
	NSLog( @"Processing REMOVE ALL ASSETS Command..." );
	return YES;
}

	
- (BOOL)processOpenCommand:(NSDictionary *)parameters
				forWebView:(UIWebView *)webView
{
	NSLog( @"Processing OPEN Command..." );
	NSString *url = [self requiredStringFromDictionary:parameters 
												forKey:@"url"];
	BOOL back = [self booleanFromDictionary:parameters
									 forKey:@"back"];
	BOOL forward = [self booleanFromDictionary:parameters
										forKey:@"back"];
	BOOL refresh = [self booleanFromDictionary:parameters
										forKey:@"back"];
	[self.bridgeDelegate openBrowser:webView 
					   withUrlString:url 
						  enableBack:back 
					   enableForward:forward 
					   enableRefresh:refresh];
	return YES;
}


- (BOOL)processRequestCommand:(NSDictionary *)parameters
				   forWebView:(UIWebView *)webView
{
	NSLog( @"Processing REQUEST Command..." );
	return YES;
}


- (BOOL)processCalendarCommand:(NSDictionary *)parameters
					forWebView:(UIWebView *)webView
{
	NSLog( @"Processing CALENDAR Command..." );
	return YES;
}


- (BOOL)processCameraCommand:(NSDictionary *)parameters
				  forWebView:(UIWebView *)webView
{
	NSLog( @"Processing CAMERA Command..." );
	return YES;
}


- (BOOL)processEMailCommand:(NSDictionary *)parameters
				 forWebView:(UIWebView *)webView
{
	NSLog( @"Processing EMAIL Command..." );
	NSString *to = [self requiredStringFromDictionary:parameters 
											   forKey:@"to"];
	NSString *subject = [self requiredStringFromDictionary:parameters 
													forKey:@"subject"];
	NSString *body = [self requiredStringFromDictionary:parameters 
												 forKey:@"body"];
	BOOL html = [self booleanFromDictionary:parameters 
									 forKey:@"html"];
	if ( ( body != nil ) && 
		 ( to != nil ) && 
		 ( subject != nil ) )
	{
		[self.bridgeDelegate sendEMailTo:to
							 withSubject:subject
								withBody:body
								  isHTML:html];
	}
	return YES;
}


- (BOOL)processPhoneCommand:(NSDictionary *)parameters
				 forWebView:(UIWebView *)webView
{
	NSString *phoneNumber = [self requiredStringFromDictionary:parameters 
														forKey:@"number"];
	NSLog( @"Processing PHONE Command for %@", phoneNumber );
	if ( ( phoneNumber != nil ) && ( phoneNumber.length > 0 ) )
	{
		[self.bridgeDelegate placeCallTo:phoneNumber];
	}
	return YES;
}


- (BOOL)processSMSCommand:(NSDictionary *)parameters
			   forWebView:(UIWebView *)webView
{
	NSLog( @"Processing SMS Command..." );
	
	NSString *to = [self requiredStringFromDictionary:parameters 
											   forKey:@"to"];
	NSString *body = [self requiredStringFromDictionary:parameters 
												 forKey:@"body"];
	if ( ( body != nil ) && 
		 ( to != nil ) )
	{
		[self.bridgeDelegate sendSMSTo:to
							  withBody:body];
	}
	return YES;
}


- (BOOL)processServiceCommand:(NSDictionary *)parameters
				   forWebView:(UIWebView *)webView
{
	// determine the desired service and state
	NSString *eventName = [parameters valueForKey:@"name"];
	NSString *desiredState = [parameters valueForKey:@"enabled"];
	BOOL enabled = ( [@"Y" isEqualToString:desiredState] );
	NSLog( @"Processing SERVICE Command to %@able %@ events", ( enabled ? @"en" : @"dis" ), eventName );
	
	if ( [@"tiltChange" isEqualToString:eventName] ) // accelerometer
	{
		if ( enabled )
		{
			m_accelerometerEnableCount++;
			if ( m_accelerometer == nil )
			{
				m_accelerometer = [[UIAccelerometer sharedAccelerometer] retain];
				m_accelerometer.updateInterval = .1;
				m_accelerometer.delegate = self;
			}
			m_processAccelerometer = YES;
		}
		else
		{
			if ( m_accelerometerEnableCount > 0 )
			{
				m_accelerometerEnableCount--;
				if ( m_accelerometerEnableCount == 0 )
				{
					m_accelerometer.delegate = nil, [m_accelerometer release], m_accelerometer = nil;
				}
			}
			m_processAccelerometer = NO;
		}
	}
	if ( [@"shake" isEqualToString:eventName] ) // shake
	{
		if ( enabled )
		{
			m_accelerometerEnableCount++;
			if ( m_accelerometer == nil )
			{
				m_accelerometer = [[UIAccelerometer sharedAccelerometer] retain];
				m_accelerometer.updateInterval = .1;
				m_accelerometer.delegate = self;
			}
			
			m_processShake = YES;
		}
		else
		{
			if ( m_accelerometerEnableCount > 0 )
			{
				m_accelerometerEnableCount--;
				if ( m_accelerometerEnableCount == 0 )
				{
					m_accelerometer.delegate = nil, [m_accelerometer release], m_accelerometer = nil;
				}
			}
			m_processShake = NO;
		}
	}
	else if ( [@"headingChange" isEqualToString:eventName] ) // compass
	{
		if ( [CLLocationManager headingAvailable] )
		{
			if ( enabled )
			{
				m_compassEnableCount++;
				if ( m_compassEnableCount == 1 )
				{
					[m_locationManager startUpdatingHeading];
				}
			}
			else
			{
				if ( m_compassEnableCount > 0 )
				{
					m_compassEnableCount--;
					if ( m_compassEnableCount == 0 )
					{
						[m_locationManager stopUpdatingHeading];
					}
				}
			}
		}
	}
	else if ( [@"locationChange" isEqualToString:eventName] ) // Location Based Services
	{
		if ( [CLLocationManager locationServicesEnabled] )
		{
			NSLog( @"Location Services are available;  Enable count: %i", m_locationEnableCount );
			if ( enabled )
			{
				m_locationEnableCount++;
				if ( m_locationEnableCount == 1 )
				{
					NSLog( @"Location Services Enabled." );
					[m_locationManager startUpdatingLocation];
				}
			}
			else
			{
				if ( m_locationEnableCount > 0 )
				{
					m_locationEnableCount--;
					if ( m_locationEnableCount == 0 )
					{
						NSLog( @"Location Services Disabled." );
						[m_locationManager stopUpdatingLocation];
					}
				}
			}
		}
		else {
			NSLog( @"Location Services are not available." );
		}
	}
	else if ( [@"networkChange" isEqualToString:eventName] ) // Reachability / Network
	{
		if ( enabled )
		{
			m_networkEnableCount++;
			if ( self.reachability == nil )
			{
				self.reachability = [Reachability reachabilityForInternetConnection];
			}
			[self.reachability startNotifier];
		}
		else
		{
			if ( m_networkEnableCount > 0 )
			{
				m_networkEnableCount--;
				if ( m_networkEnableCount == 0 )
				{
					[self.reachability stopNotifier];
					self.reachability = nil;
				}
			}
		}
	}
	else if ( [@"rotationChange" isEqualToString:eventName] ) // gyroscope
	{
		if ( self.motionManager != nil )
		{
			if ( enabled )
			{
				m_gyroscopeEnableCount++;
				if ( m_timer == nil )
				{
					m_timer = [NSTimer scheduledTimerWithTimeInterval:0.1 
															   target:self
															 selector:@selector(timerFired)
															 userInfo:nil 
															  repeats:YES];
					[self.motionManager startGyroUpdates];
				}
			}
			else
			{
				if ( m_gyroscopeEnableCount > 0 )
				{
					m_gyroscopeEnableCount--;
					if ( m_gyroscopeEnableCount == 0 )
					{
						[self.motionManager stopGyroUpdates];
					}
				}
			}
		}
	}
	
	// anything else is not something that we need to enable or disable
	
	return YES;
}


// restore to default state
- (void)restoreServicesToDefaultState
{
	// accelerometer monitoring
	if ( m_accelerometerEnableCount > 0 )
	{
		m_accelerometer.delegate = nil, [m_accelerometer release], m_accelerometer = nil;
		m_accelerometerEnableCount = 0;
	}
	
	// compass monitoring
	if ( m_compassEnableCount > 0 )
	{
		[m_locationManager stopUpdatingHeading];
		m_compassEnableCount = 0;
	}
	
	// gyroscope monitoring
	if ( m_gyroscopeEnableCount > 0 )
	{
		[m_timer invalidate], m_timer = nil;
		[self.motionManager stopGyroUpdates];
		m_gyroscopeEnableCount = 0;
	}
	
	// location monitoring
	if ( m_locationEnableCount > 0 )
	{
		[m_locationManager stopUpdatingLocation];
		m_locationEnableCount = 0;
	}
	
	// network monitoring
	if ( m_networkEnableCount > 0 )
	{
		if ( self.reachability != nil )
		{
			[self.reachability stopNotifier];
			self.reachability = nil;
		}
		m_networkEnableCount = 0;
	}
}


#pragma mark -
#pragma mark Notification Center Dispatch Methods

- (void)orientationChanged:(NSNotification *)notification
{
	UIDevice *device = [UIDevice currentDevice];
	UIDeviceOrientation orientation = device.orientation;
	NSInteger orientationAngle = -1;
	switch ( orientation )
	{
		case UIDeviceOrientationPortrait:
			orientationAngle = 0;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			orientationAngle = 180;
			break;
		case UIDeviceOrientationLandscapeLeft:
			orientationAngle = 270;
			break;
		case UIDeviceOrientationLandscapeRight:
			orientationAngle = 90;
			break;
		default:
			// the device is likely flat
			// since we have no idea what the orientation is
			// don't change it
			return;
	}
	CGSize screenSize = [device screenSizeForOrientation:orientation];
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
					executeJavascript:@"window.ormmaview.fireChangeEvent( { orientation: %i, screenSize: { width: %f, height: %f } } );", orientationAngle,
																																		  screenSize.width, screenSize.height];
}


- (void)reachabilityStateChanged:(NSNotification *)notification
{
	NSString *state = @"offline";
	Reachability *r = (Reachability *)notification.object;
	if ( [r isReachableViaWWAN] )
	{
		state = @"cell";
	}
	else if ( [r isReachableViaWiFi] )
	{
		state = @"wifi";
	}
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
					executeJavascript:@"window.ormmaview.fireChangeEvent( { network: '%@' } );", state];
}


- (void)keyboardWillShow:(NSNotification *)notification
{
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
	 executeJavascript:@"window.ormmaview.fireChangeEvent( { keyboardState: true } );"];
}


- (void)keyboardWillHide:(NSNotification *)notification
{
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
					executeJavascript:@"window.ormmaview.fireChangeEvent( { keyboardState: false } );"];
}



#pragma mark -
#pragma mark Accelerometer Delegete

- (void)accelerometer:(UIAccelerometer *)accelerometer 
		didAccelerate:(UIAcceleration *)acceleration
{
	static BOOL processingShake = NO;
	BOOL shake = NO;
	
	// send accelerometer data if needed
	if ( m_processAccelerometer )
	{
	    NSLog( @"Acceleration Data Available: %f, %f, %f", acceleration.x,
														   acceleration.y,
														   acceleration.z );
		[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
						executeJavascript:@"window.ormmaview.fireChangeEvent( { tilt: { x: %f, y: %f, z: %f } } );", acceleration.x,
																												acceleration.y,
																												acceleration.z];
	}
	
	// deal with shakes
	if ( m_processShake )
	{
	   if ( processingShake )
	   {
		   return;
	   }
	   if ( ( acceleration.x > m_shakeIntensity ) || ( acceleration.x < ( -1 * m_shakeIntensity ) ) )
	   {
		   shake = YES;
	   }
	   if ( ( acceleration.x > m_shakeIntensity ) || ( acceleration.x < ( -1 * m_shakeIntensity ) ) )
	   {
		  shake = YES;
  	   }
	   if ( ( acceleration.x > m_shakeIntensity ) || ( acceleration.x < ( -1 * m_shakeIntensity ) ) )
	   {
		  shake = YES;
	   }
	
	   if ( shake )
	   {
		   // Shake detected
		   NSLog( @"Shake Detected" );
		   [self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
						   executeJavascript:@"window.ormmaview.fireShakeEvent();"];
	   }
	   processingShake = NO;
	}
}


#pragma mark -
#pragma mark Timer Handler

- (void)timerFired
{
	// get the current gyroscope data
	CMGyroData *data = self.motionManager.gyroData;
	NSLog( @"Gyroscope Data Available: %f, %f, %f", data.rotationRate.x, 
													data.rotationRate.y, 
													data.rotationRate.z );
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
					executeJavascript:@"window.ormmaview.fireChangeEvent( { rotation: { x: %f, y: %f, z: %f } } );", data.rotationRate.x, 
																									   data.rotationRate.y, 
																									   data.rotationRate.z];
}



#pragma mark -
#pragma mark Location Manager Delegate (including Compass)

- (void)locationManager:(CLLocationManager *)manager 
	didUpdateToLocation:(CLLocation *)newLocation 
		   fromLocation:(CLLocation *)oldLocation
{
	NSLog( @"Location Data Available: (%f, %f ) acc: %f", newLocation.coordinate.latitude, 
														  newLocation.coordinate.longitude, 
														  newLocation.horizontalAccuracy );
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
					executeJavascript:@"window.ormmaview.fireChangeEvent( { location: { lat: %f, lon: %f, acc: %f } } );", newLocation.coordinate.latitude, 
																											 newLocation.coordinate.longitude, 
																											 newLocation.horizontalAccuracy];
}


- (void)locationManager:(CLLocationManager *)manager 
	   didFailWithError:(NSError *)error

{
}


- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager
{
	// TODO: We may want to show a calibration screen based on the accuracy of 
	// the heading
	return NO;
}


- (void)locationManager:(CLLocationManager *)manager 
	   didUpdateHeading:(CLHeading *)newHeading
{ 
	NSLog( @"Heading Data Available: %f", newHeading.trueHeading );
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
	[formatter setTimeStyle:NSDateFormatterFullStyle];
	[formatter setDateStyle:NSDateFormatterFullStyle];
	[self.bridgeDelegate usingWebView:self.bridgeDelegate.currentWebView
					executeJavascript:@"window.ormmaview.fireChangeEvent( { heading: %f } );", newHeading.trueHeading];
}


- (void)locationManager:(CLLocationManager *)manager 
		 didEnterRegion:(CLRegion *)region
{
}


- (void)locationManager:(CLLocationManager *)manager 
		  didExitRegion:(CLRegion *)region
{
}


- (void)locationManager:(CLLocationManager *)manager 
monitoringDidFailForRegion:(CLRegion *)region 
			  withError:(NSError *)error
{
}



#pragma mark -
#pragma mark Utility

- (CGFloat)floatFromDictionary:(NSDictionary *)dictionary
						forKey:(NSString *)key
{
	return [self floatFromDictionary:dictionary
							  forKey:key
						 withDefault:0.0];
}


- (CGFloat)floatFromDictionary:(NSDictionary *)dictionary
						forKey:(NSString *)key
				   withDefault:(CGFloat)defaultValue
{
	NSString *stringValue = [dictionary valueForKey:key];
	if ( stringValue == nil )
	{
		return defaultValue;
	}
	CGFloat value = [stringValue floatValue];
	return value;
}


- (BOOL)booleanFromDictionary:(NSDictionary *)dictionary
					   forKey:(NSString *)key
{
	NSString *stringValue = [dictionary valueForKey:key];
	BOOL value = [@"Y" isEqualToString:stringValue] || [@"y" isEqualToString:stringValue];
	return value;
}


- (NSString *)requiredStringFromDictionary:(NSDictionary *)dictionary
									forKey:(NSString *)key
{
	NSString *value = [dictionary objectForKey:key];
	if ( value == nil )
	{
		// error
		NSLog( @"Missing required parameter: %@", key );
		return nil;
	}
	value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ( value.length == 0 )
	{
		NSLog( @"Missing required parameter: %@", key );
		return nil;
	}
	return value;
}

@end
