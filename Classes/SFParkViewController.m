//
//  SFParkViewController.m
//  SFPark
//
// iPhone development by Brian VanderZanden and Mark S. Morris ( http://mmorrisdev.com )
// 

/*
 * Copyright 2011 SFMTA
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import "ASIHTTPRequest.h"
#import "SFParkViewController.h"
#import "JSON/JSON.h"
#import "MyPolyline.h"
#import "MyAnnotation.h"
#import <unistd.h>

//#define DEBUG		//flag now in preprocessor macro debug configuration
//#define WALKINGSPEED
//#define FORCESPEEDCURTAIN

#define MAXIMUM_ZOOM 20

@implementation SFParkViewController

@synthesize mapView = _mapView;
@synthesize locationManager;
@synthesize availabilityButton;
@synthesize priceButton;
@synthesize lineColor;
@synthesize interestAreas;
@synthesize blockfaces;
@synthesize returnData;
@synthesize startTime;
@synthesize serviceURL;

//mpsvalue × 100 × 3600 / (2.54 × 12 × 5280) //mph to mps
#ifdef WALKINGSPEED
static float SPEED_THRESHOLD = 1.1176; // 2.5 mph == 1.1176 mps Walking speed test threshold
#else
static float SPEED_THRESHOLD = 4.47; // 10.0 mph == 4.47 mps Driving speed threshold
#endif
static CLLocationDegrees INITIAL_LATITUDE = 37.78; // SF initial view
static CLLocationDegrees INITIAL_LONGITUDE = -122.42; // SF initial view


#pragma mark -
#pragma mark Standard methods

// Fire things off.
- (void) viewDidLoad{
	[super viewDidLoad];
	[self showDisclaimer];
#ifdef DEBUG
	[buildNumber setHidden:NO];
#else
	[buildNumber setHidden:YES];
#endif
	self.interestAreas = [[NSMutableArray alloc] init];
	self.blockfaces = [[NSMutableArray alloc] init];
	[availabilityButton setSelected:YES];
	
	
	stillLoading = YES;
	stillDisplayingIntroView = YES;
	showPrice = NO;
	seenDisclaimer = NO;
	displayingDetails = NO;
	lowMemoryMode = NO;
	veryLowMemoryMode = NO;
	//Live data source
	serviceURL = @"http://api.sfpark.org/sfpark/rest/availabilityservice?radius=2.0&response=json&pricing=yes&version=1.3";
	
	//Sunday url
	//serviceURL = @"http://b4.sfpark.org/staticdata/availability-WeekEnd-Sun-0859AM.json";
	
	//Test harness url
	//serviceURL = @"http://b4.sfpark.org/staticdata/testharness.json";
    	
	//Map setup
	MKCoordinateRegion region;
	MKCoordinateSpan span;
	span.latitudeDelta  = 0.06;
	span.longitudeDelta = 0.06;
	CLLocationCoordinate2D location = self.mapView.userLocation.coordinate;
	location.latitude  = INITIAL_LATITUDE;
	location.longitude = INITIAL_LONGITUDE;
	region.span = span;
	region.center = location;
	self.mapView.showsUserLocation = TRUE;
	[self.mapView setRegion:region animated:TRUE];
	[self.mapView regionThatFits:region];
    
    iconArray[0]  = [[UIImage imageNamed:@"invalid_garage"] retain];
	iconArray[1]  = [[UIImage imageNamed:@"street_invalid"] retain];
	iconArray[2]  = [[UIImage imageNamed:@"garage_availability_high"] retain];
	iconArray[3]  = [[UIImage imageNamed:@"street_availability_high"] retain];
	iconArray[4]  = [[UIImage imageNamed:@"street_availability_medium"] retain];
	iconArray[5]  = [[UIImage imageNamed:@"garage_availability_medium"] retain];		
	iconArray[6]  = [[UIImage imageNamed:@"garage_availability_low"] retain];
	iconArray[7]  = [[UIImage imageNamed:@"street_availability_low"] retain];
	iconArray[8]  = [[UIImage imageNamed:@"street_price_low"] retain];
	iconArray[9]  = [[UIImage imageNamed:@"street_price_medium"] retain];
	iconArray[10] = [[UIImage imageNamed:@"street_price_high"] retain];
	iconArray[11] = [[UIImage imageNamed:@"garage_price_low"] retain];
	iconArray[12] = [[UIImage imageNamed:@"garage_price_medium"] retain];
	iconArray[13] = [[UIImage imageNamed:@"garage_price_high"] retain];

}

// deallocate resources.
- (void) dealloc{
	[super dealloc];
	[self.interestAreas release];
	[self.blockfaces release];
	[self.returnData release];
	[startTime release];
}

// Display the app either right-side up or upside down. No landscape.
- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	if (interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown || interfaceOrientation == UIInterfaceOrientationPortrait) {
		return YES;
	} else {
		return NO;
	}
}

- (BOOL) canBecomeFirstResponder {
	return YES;
}

- (void) viewDidAppear:(BOOL)animated {
	[self becomeFirstResponder];
	[super viewDidAppear:animated];
}

- (void) viewDidDisappear:(BOOL)animated {
	[self resignFirstResponder];
	[super viewDidDisappear:animated];
}

- (void) didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	return;
}

#pragma mark -
#pragma mark Interface Outlets

// Switch on Availability mode
- (IBAction) showAvailability: (id)sender{
	// If we're not already in availability mode, change to it.
	if (showPrice == YES){
		showPrice = NO;
		[self hideAllActivityIndicators];
		HUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
		HUD.labelText = @"Loading availability display";
		[self performSelector:@selector(displayData) withObject:nil afterDelay:0];

	}
	[availabilityButton setSelected:YES];
	[priceButton setSelected:NO];
	legendlabel.text = @"Availability";
	legendlabel.accessibilityLabel = @"Availability display";
	UIImage *legendImage = [UIImage imageNamed:@"key_availability"];
	[legend setImage:legendImage ];
	UIImage *buttonImage = [UIImage imageNamed:@"button_availability_active"];
	[availabilityButton setImage:buttonImage forState:(UIControlStateHighlighted|UIControlStateSelected)];
	UIImage *priceImage = [UIImage imageNamed:@"button_pricing_up"];
	[self.priceButton setImage:priceImage forState:UIControlStateSelected|UIControlStateNormal|UIControlStateHighlighted];
}

// Switch on Pricing mode
- (IBAction) showPricing: (id)sender{
	// If we're not already in price mode, reload it in price display configuration
	if (showPrice == NO){
		showPrice = YES;
		[self hideAllActivityIndicators];
		HUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
		HUD.labelText = @"Loading pricing display";
		[self performSelector:@selector(displayData) withObject:nil afterDelay:0];
	}
	[priceButton setSelected:YES];
	[availabilityButton setSelected:NO];
	legendlabel.text = @"Price";
	legendlabel.accessibilityLabel = @"Price display";
	UIImage *legendImage = [UIImage imageNamed:@"key_pricing"];
	[legend setImage:legendImage ];
	UIImage *priceImage = [UIImage imageNamed:@"button_pricing_active"];
	[self.priceButton setImage:priceImage forState:UIControlStateSelected|UIControlStateNormal|UIControlStateHighlighted];
	UIImage *buttonImage = [UIImage imageNamed:@"button_availability_up"];
	[availabilityButton setImage:buttonImage forState:(UIControlStateHighlighted|UIControlStateSelected)];
}

// Refresh the data from the server.
- (IBAction) refresh: (id)sender{
	double gpsSpeed = 0.0;
	ageOfData.text =  [NSString stringWithFormat:@"%5.2fMPH",gpsSpeed];
	[self hideAllActivityIndicators];
	HUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
	HUD.labelText = @"Refreshing data.";
	[self performSelector:@selector(loadData) withObject:nil afterDelay:0];

}

// Reload the data on a shake event.
- (void) motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event{
	if (event.subtype == UIEventSubtypeMotionShake){
		[self hideAllActivityIndicators];
		HUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
		HUD.labelText = @"Shaken. Refreshing data.";
		[self performSelector:@selector(loadData) withObject:nil afterDelay:0];

	}
	[super motionEnded:motion withEvent:event];
}

#pragma mark -
#pragma mark Data loading methods

// Load all the data from the API server.
- (void) loadData{
	startTime = [NSDate date];
	[startTime retain];
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
	//responseData = [[NSMutableData data] retain];
	NSString * whichService;
	// Kitchen sink it.  Load everything... (But gzip the payload)
	whichService = serviceURL;
	NSURL *url = [NSURL URLWithString:whichService];
	ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
	[request addRequestHeader:@"Accept-Encoding" value:@"gzip"];
	[request addRequestHeader:@"User-Agent" value:@"sfpark-iphone-app"];
    [request setAllowCompressedResponse:YES];
	[request setNumberOfTimesToRetryOnTimeout:5];
	[request setDelegate:self];
	[request setDidFinishSelector:@selector(requestFinished:)];
	[request setDidFailSelector:@selector(requestFailed:)];
	[request startAsynchronous];
	self.locationManager = [[[CLLocationManager alloc] init] autorelease];
	locationManager.delegate = self;
	locationManager.distanceFilter = kCLDistanceFilterNone;
	[locationManager startUpdatingLocation];
}

//ASIHTTPRequest delegate method
- (void) requestFinished:(ASIHTTPRequest *)request{
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	/*
	NSString *contentLengthString = [[request responseHeaders] objectForKey:@"Content-Length"];
	double contentlength = [contentLengthString doubleValue];
	howLong = [startTime timeIntervalSinceNow];
	label.text = [NSString stringWithFormat:@"%6.3fs|%@b|%6.3fb/s",
								-howLong,
								[[request responseHeaders] objectForKey:@"Content-Length"],
								(contentlength / (-howLong))];
	*/
	NSError *error;
    // TODO: Profile other json parsers and see if there's an appreciable speedup.
	SBJSON *json = [SBJSON new];
	NSDictionary * dObj = [json objectWithString:[request responseString] error:&error];
	//self.returnData = [json objectWithString:[request responseString] error:&error];
	self.returnData = dObj;
	[json release];
	
	json = nil;
	[self performSelector:@selector(displayData) withObject:nil afterDelay:0];	
}

//ASIHTTPRequest delegate method
- (void) requestFailed:(ASIHTTPRequest *)request{
	//NSError *error = [request error];
	label.text = @"There was an error loading the parking data.";
	[self hideAllActivityIndicators];
	UIAlertView* alertView = nil; 
	@try { 
        alertView = [[UIAlertView alloc] initWithTitle:@"Unable to fetch data from server" message:@"Please try again." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil]; 
        [alertView show]; 
	} @finally { 
        if (alertView) { 
            [alertView release]; 
        } 
	}
}

#pragma mark -
#pragma mark Data display methods

- (void) displayData{
	stillLoading = YES;
	if (self.returnData == nil){
		label.text = @"Data parsing failed";
		[self hideAllActivityIndicators];
		
		UIAlertView* alertView = nil; 
		@try { 
			alertView = [[UIAlertView alloc] initWithTitle:@"Unable to read parking data" message:@"Please try again." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil]; 
			
			[alertView show]; 
		} @finally { 
			if (alertView) { 
				[alertView release]; 
			} 
		}
		
	} else {
		NSArray * data = [self.returnData objectForKey:@"AVL"];
		//NSString * updatedTime = [self.returnData objectForKey:@"AVAILABILITY_UPDATED_TIMESTAMP"];
		NSString * recievedTime = [self.returnData objectForKey:@"AVAILABILITY_REQUEST_TIMESTAMP"];
		//NSLog(@"recTime %@",recievedTime);
		// 4/7/11: API server timezone info changed from -08:00 to -07:00. Asking for the addition of "GMT" + offset to insulate from any string changes required here.
		NSString *cleanedTimeZone = [recievedTime stringByReplacingOccurrencesOfString:@"-07:00" withString:@"GMT-07:00"]; // Need to add 'GMT' to the time string to be able to use the NSDateFormatter with the ZZZZ directive.
		//NSLog(@"cleanedtimezone 1: %@",cleanedTimeZone);
		cleanedTimeZone = [cleanedTimeZone stringByReplacingOccurrencesOfString:@"-08:00" withString:@"GMT-08:00"]; // Need to add 'GMT' to the time string to be able to use the NSDateFormatter with the ZZZZ directive.
		//NSLog(@"cleanedtimezone 2: %@",cleanedTimeZone);
		NSDateFormatter *df = [[NSDateFormatter alloc] init];
		[df setDateFormat:@"yyyy-MM-dd'T'H:mm:ss'.'SSSZZZZ"];
		NSDate *cleanRecievedTime = [df dateFromString: cleanedTimeZone];
		//NSLog(@"cleanedtimezone 3: %@",cleanedTimeZone);
		NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
		[dateFormatter setDateFormat:@"h:mma"];
		NSString *strDate = [dateFormatter stringFromDate:cleanRecievedTime];
		[dateFormatter release];
		[df release];
		
		if (showPrice) {
			legendlabel.text = [NSString stringWithFormat:@"Price as of %@",strDate];
		} else {
			legendlabel.text = [NSString stringWithFormat:@"Availability as of %@",strDate];
		}
		

		[self.mapView removeAnnotations:self.mapView.annotations];
		// remove any overlays that exist
		[self.mapView removeOverlays:self.mapView.overlays];

		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		for(id element in data){
			if([element objectForKey:@"LOC"]){
				NSString * loc = [element objectForKey:@"LOC"];
				NSArray *blockPoints = [loc componentsSeparatedByString: @","];
				int numberOfPoints = [[element objectForKey:@"PTS"] intValue];
				CLLocationCoordinate2D  location;
				if (numberOfPoints  == 2) {
					location.latitude = (([[blockPoints objectAtIndex:1] doubleValue] + [[blockPoints objectAtIndex:3] doubleValue]) / 2.0);
					location.longitude= (([[blockPoints objectAtIndex:0] doubleValue] + [[blockPoints objectAtIndex:2] doubleValue]) / 2.0);
				} else {
					location.latitude = [[blockPoints objectAtIndex:1] floatValue];
					location.longitude= [[blockPoints objectAtIndex:0] floatValue];
				}

				MyAnnotation* interestArea = [[MyAnnotation alloc] initWithData:element andLocation:location];
				interestArea.timeStamp = cleanRecievedTime;
				if (numberOfPoints == 2) { // Two points, it's a block of on-street parking
						CLLocationCoordinate2D  points[2];
						points[0] = CLLocationCoordinate2DMake([[blockPoints objectAtIndex:1] floatValue],[[blockPoints objectAtIndex:0] floatValue]);
						points[1] = CLLocationCoordinate2DMake([[blockPoints objectAtIndex:3] floatValue],[[blockPoints objectAtIndex:2] floatValue]);					
                        MyPolyline* poly = (MyPolyline*)[MyPolyline polylineWithCoordinates:points count:numberOfPoints];
                        poly.lineColor = [interestArea blockfaceColorizerWithShowPrice:showPrice];
						[self.blockfaces addObject:poly];
						[self.mapView addOverlay:poly];
				}
				// TODO: Implement something akin to this for a future where there are many points...
				//[mapView isCoordinateInVisibleRegion:myCoordinate]
				
                [self.mapView addAnnotation:interestArea];
                if ([self inClose]) {
                    displayingDetails = YES;
                }
				[interestArea release];
			}
		}						   
		[pool release];
	}
	stillLoading = NO;
}

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views{
	if (stillLoading){
		return;
    }
	[self hideAllActivityIndicators];

}


- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated{
	if (stillDisplayingIntroView)
		return;

	if ( !displayingDetails && !lowMemoryMode && [self inClose]){
		HUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
		HUD.labelText = @"Processing detailed display.";
		[self performSelector:@selector(displayData) withObject:nil afterDelay:0];
	}
}


// Determine, arbitrarily, how closely we are zoomed in. If past a certain theshold (15?), return "close"
- (BOOL) inClose{
	NSUInteger zoomLevel = [self zoomLevelForMapRect:self.mapView.visibleMapRect withMapViewSizeInPixels: self.mapView.bounds.size];
	//NSLog(@"zoom level = %d",zoomLevel);
	if (lowMemoryMode){
		if( zoomLevel > 18) {
			return YES;
		}
	} else	if (zoomLevel > 13 || ([self isOldHardware:[self platform]] && zoomLevel > 16)) {
		return YES;
	} else {
		return NO;
	}
	return NO;
}

// Figure out how closely in we are zoomed.
- (NSUInteger) zoomLevelForMapRect:(MKMapRect)mRect withMapViewSizeInPixels:(CGSize)viewSizeInPixels{
	NSUInteger zoomLevel = MAXIMUM_ZOOM; // MAXIMUM_ZOOM is 20 with MapKit
	MKZoomScale zoomScale = mRect.size.width / viewSizeInPixels.width; //MKZoomScale is just a CGFloat typedef
	double zoomExponent = log2(zoomScale);
	zoomLevel = (NSUInteger)(MAXIMUM_ZOOM - ceil(zoomExponent));
	return zoomLevel;
}

// GarageDetailsViewController display done. 
- (void) garageDetailsViewControllerDidFinish:(GarageDetailsViewController *)controller {	
	UIView *subView = [self.view viewWithTag:23];
	[subView removeFromSuperview];
}

#pragma mark -
#pragma mark Speed curtain methods

// Load speed warning view.
- (void) speedWarning{
#ifdef FORCESPEEDCURTAIN
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"speedWarningAcknowledged"]; // Force disclaimer screen for testing
#endif
	seenDisclaimer = [[NSUserDefaults standardUserDefaults] boolForKey:@"speedWarningAcknowledged"];
	if(! seenDisclaimer){
		label.text = @"speedwarning";
		[locationManager stopUpdatingLocation];
		SpeedingViewController *controller = [[SpeedingViewController alloc] initWithNibName:@"SpeedingView" bundle:nil];
		controller.delegate = self;
		controller.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
		[self presentModalViewController:controller animated:YES];
		[controller release];
	}
}

// Start updating location again, as the speed warning view is gone.
- (void) speedViewControllerDidFinish:(SpeedingViewController *)controller {
	[self dismissModalViewControllerAnimated:YES];
	[locationManager startUpdatingLocation];
	label.text = @"speedwarning finished.";
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"speedWarningAcknowledged"];
	[self displayData];
}

// Check if the speed returned is above the warning threshold.
- (BOOL) isMovingTooFastNewLocation:(CLLocation *) newLocation OldLocation: (CLLocation *) oldLocation{
	//return YES; // for debug
	//FEATURE: Perhaps improve this to check if the moving average speed is above the threshold rather than instantantaneous speed.
	if (newLocation.speed > SPEED_THRESHOLD) {
		return YES;
	}else {
		return NO;
	}
}

// Check if the speed returned is above the warning threshold.
- (void) locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation{
	double gpsSpeed = newLocation.speed;
	if (gpsSpeed >= 0.0) {
		gpsSpeed *= MPSTOMPH; // Convert meters per second to miles per hour.
		ageOfData.textColor = [UIColor whiteColor];
		ageOfData.numberOfLines = 1;
		ageOfData.adjustsFontSizeToFitWidth = YES;
		ageOfData.text = [NSString stringWithFormat:@"%5.2fMPH",gpsSpeed];
		if([self isMovingTooFastNewLocation:newLocation OldLocation:oldLocation]){
			label.text = @"Moving too fast.\nSpeed warning!";
			[self speedWarning];
		}
	}
}

#pragma mark -
#pragma mark Credits display

//Credits display
- (IBAction) showInfo:(id)sender {
	label.numberOfLines = 1;
	label.text = @"Loading info screen.";
	FlipsideViewController *controller = [[FlipsideViewController alloc] initWithNibName:@"Credits" bundle:nil];
	controller.delegate = self;
	controller.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
	[self presentModalViewController:controller animated:YES];
	[controller release];
}

// Credits display done. 
- (void) flipsideViewControllerDidFinish:(FlipsideViewController *)controller {	
	[self dismissModalViewControllerAnimated:YES];
	label.text = @"Back from the credits screen.";
}

#pragma mark -
#pragma mark IntroViewController methods

// Show the introduction / disclaimer screen. 
- (void) showDisclaimer{
	IntroViewController *introViewController = [[IntroViewController alloc] initWithNibName:@"IntroView" bundle:[NSBundle mainBundle]];
	introViewController.delegate = self;
	[self.view addSubview:introViewController.view];
	[introViewController release];
}

// Introduction display done. 
- (void) introViewControllerDidFinish:(IntroViewController *)controller
{	
	UIView *subView = [self.view viewWithTag:23];
	[subView removeFromSuperview];
	if (stillDisplayingIntroView) {
		stillDisplayingIntroView = NO;
	}
	if (stillLoading)
	{
		stillLoading = NO;
		HUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
		HUD.labelText = @"Loading data.";

	}
//	[self loadData];
	[self performSelector:@selector(loadData) withObject:nil afterDelay:0];		//let the message loop run a bit first.

#ifdef FORCESPEEDCURTAIN
	[self speedWarning];
#endif
}

#pragma mark -
#pragma mark Map overlay methods

// Setup map's overlay data properties.
- (MKOverlayView *) mapView:(MKMapView *)mapView viewForOverlay:(id)overlay
{
    if (!MKMapRectIntersectsRect([overlay boundingMapRect], mapView.visibleMapRect))
		return nil; //MSM test
    
	if ([overlay isKindOfClass:[MKPolygon class]]){
		MKPolygonView*    aView = [[[MKPolygonView alloc] initWithPolygon:(MKPolygon*)overlay] autorelease];
		aView.fillColor = self.lineColor;
		aView.strokeColor = self.lineColor;
		aView.lineWidth = 8;
		return aView;
	}else{
        MyPolyline *thisLine = (MyPolyline*)overlay;
		MKPolylineView *polyLineView = [[[MKPolylineView alloc] initWithOverlay:overlay] autorelease];
		polyLineView.strokeColor = thisLine.lineColor;
		polyLineView.lineWidth = 8.0;
		return polyLineView;
	}
}

- (MKAnnotationView *) mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation{
	if ([annotation isKindOfClass:[MKUserLocation class]]){
		return nil;
	}
	// Try to dequeue an annotation first...
	MKAnnotationView *pointOfInterestIcon = nil;
	static NSString *defaultID = @"annotationID";
	pointOfInterestIcon = (MKAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:defaultID];
	if ( pointOfInterestIcon == nil ){
		pointOfInterestIcon = [[[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:defaultID] autorelease];
        UIButton *rightButton = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        [rightButton addTarget:self action:@selector(showDetails:) forControlEvents:UIControlEventTouchUpInside];
        pointOfInterestIcon.rightCalloutAccessoryView = rightButton;
        pointOfInterestIcon.canShowCallout = YES;
	}

	int itemImageName;
	MyAnnotation * currentAnnotation = (MyAnnotation *)annotation;
	currentAnnotation.subtitle = 	[currentAnnotation availabilityDescriptionShowingPrice:showPrice];
	itemImageName = [currentAnnotation iconFinder:showPrice];
	if ((itemImageName >= 0) && (itemImageName <= 13)){ // Upper and lower bounds for the index mapping into the different icons.
		[pointOfInterestIcon setImage:iconArray[itemImageName]];
	}
    pointOfInterestIcon.rightCalloutAccessoryView.tag = (int)annotation;
	[(UIButton*)pointOfInterestIcon.rightCalloutAccessoryView setTitle:annotation.title forState:UIControlStateNormal];

	return pointOfInterestIcon;
}

// Load up another view with the details of the currently selected garage or street.
- (IBAction) showDetails:(UIView *)sender{
	MyAnnotation* currentSelection = (MyAnnotation*)sender.tag;
	GarageDetailsViewController *garageDetailsViewController = [[GarageDetailsViewController alloc] initWithNibName:@"GarageDetailsView" bundle:[NSBundle mainBundle]];
	garageDetailsViewController.delegate = self;
	garageDetailsViewController.thisGarage = currentSelection;
	
	garageDetailsViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;		//default is UIModalTransitionStyleCoverVertical
	[self presentModalViewController:garageDetailsViewController animated:YES];  
}

#pragma mark -
#pragma mark Launch directions in map app

//FEATURE: Use this type of code structure to create and action sheet warning to launch off the maps app in directions mode for the user's current location and the selected destination.
/*
 CLLocationCoordinate2D start = { 34.052222, -118.243611 };
 CLLocationCoordinate2D destination = { 37.322778, -122.031944 };        
 
 NSString *googleMapsURLString = [NSString stringWithFormat:@"http://maps.google.com/?saddr=%1.6f,%1.6f&daddr=%1.6f,%1.6f",
 start.latitude, start.longitude, destination.latitude, destination.longitude];
 [[UIApplication sharedApplication] openURL:[NSURL URLWithString:googleMapsURLString]];
 */



#pragma mark -
#pragma mark MBProgressHUDDelegate methods

- (void) hudWasHidden {
	[HUD removeFromSuperview];
	[HUD release];
}

- (void) HUDrefreshing {
 HUD.mode = MBProgressHUDModeDeterminate;
 HUD.detailsLabelText = @"Loading";
 float progress = 0.0f;
 while (progress < 1.0f){
	 progress += 0.01f;
	 HUD.progress = progress;
	 //usleep(500);
 }
}

- (void) hideAllActivityIndicators {
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	stillLoading = NO;
	[MBProgressHUD hideHUDForView:self.view animated:YES];
}


#pragma mark -
#pragma mark Device detection

// Determine the device the app is running on.
- (NSString *) platform{
	size_t size;
	sysctlbyname("hw.machine", NULL, &size, NULL, 0);
	char *machine = malloc(size);
	sysctlbyname("hw.machine", machine, &size, NULL, 0);
	NSString *platform = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
	free(machine);
	if ([platform isEqualToString:@"iPhone1,1"])    return @"iPhone 1G";
	if ([platform isEqualToString:@"iPhone1,2"])    return @"iPhone 3G";
	if ([platform isEqualToString:@"iPhone2,1"])    return @"iPhone 3GS";
	if ([platform isEqualToString:@"iPhone3,1"])    return @"iPhone 4";
	if ([platform isEqualToString:@"iPhone3,2"])    return @"Verizon iPhone 4";
	if ([platform isEqualToString:@"iPod1,1"])      return @"iPod Touch 1G";
	if ([platform isEqualToString:@"iPod2,1"])      return @"iPod Touch 2G";
	if ([platform isEqualToString:@"iPod3,1"])      return @"iPod Touch 3G";
	if ([platform isEqualToString:@"iPod4,1"])      return @"iPod Touch 4G";
	if ([platform isEqualToString:@"iPad1,1"])      return @"iPad";
	if ([platform isEqualToString:@"iPad2,1"])      return @"iPad 2 (WiFi)";
	if ([platform isEqualToString:@"iPad2,2"])      return @"iPad 2 (GSM)";
	if ([platform isEqualToString:@"iPad2,3"])      return @"iPad 2 (CDMA)";
	if ([platform isEqualToString:@"i386"])         return @"Simulator";
	return platform;
}

// Arbitrary measure of 'oldness' of particular hardware.
- (BOOL) isOldHardware:(NSString *) platformString{
	return NO; //MSM
	//These are the list of devices with only 128MB RAM.
	if ([platformString isEqualToString:@"iPhone 1G"])    return YES;
	if ([platformString isEqualToString:@"iPhone 3G"])    return YES;
	if ([platformString isEqualToString:@"iPod Touch 1G"])      return YES;
	if ([platformString isEqualToString:@"iPod Touch 2G"])      return YES;
	return NO;
}


@end