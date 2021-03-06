//
//  KPPhotoOrderViewController.m
//  KindredPrints-iOS-SDK
//
//  Created by Alex Austin on 1/31/14.
//
//

#import "KPPhotoOrderController.h"
#import "KPCartPageViewController.h"
#import "KPPhotoSelectViewController.h"
#import "KPLoadingScreenViewController.h"
#import "UserPreferenceHelper.h"
#import "DevPreferenceHelper.h"
#import "ImageManager.h"
#import "BaseImage.h"
#import "OrderImage.h"
#import "KindredServerInterface.h"
#import "OrderManager.h"
#import "Mixpanel.h"

@interface KPPhotoOrderController() <ServerInterfaceDelegate, ImageManagerDelegate, OrderManagerDelegate>

@property (strong, nonatomic) NSMutableArray *queuedImages;
@property (strong, nonatomic) NSMutableArray *incomingImages;
@property (strong, nonatomic) KPLoadingScreenViewController *loadingVC;
@property (strong, nonatomic) KindredServerInterface *ksInterface;
@property (nonatomic) NSInteger outstandingConfigNecessary;
@property (nonatomic) NSInteger returnedConfigNecessary;

@property (strong, nonatomic) OrderManager *orderManager;

@property (nonatomic) BOOL showSelect;
@property (nonatomic) BOOL isLoading;

@property (strong, nonatomic) Mixpanel *mixpanel;

@end

@implementation KPPhotoOrderController

static NSInteger PHOTO_THRESHOLD = 10;

- (Mixpanel *)mixpanel {
    if (!_mixpanel) {
        _mixpanel = [Mixpanel sharedInstanceWithToken:@"258130d00d97e7bb9f05cac89a070060"];
    }
    return _mixpanel;
}

- (NSMutableArray *)incomingImages {
    if (!_incomingImages) {
        _incomingImages = [[NSMutableArray alloc] init];
    }
    return _incomingImages;
}

- (NSMutableArray *)queuedImages {
    if (!_queuedImages) {
        _queuedImages = [[NSMutableArray alloc] init];
    }
    return _queuedImages;
}

- (KindredServerInterface *)ksInterface {
    if (!_ksInterface) {
        _ksInterface = [[KindredServerInterface alloc] init];
        _ksInterface.delegate = self;
    }
    return _ksInterface;
}

- (OrderManager *)orderManager {
    if (!_orderManager) {
        _orderManager = [OrderManager getInstance];
    }
    return _orderManager;
}

-(BOOL)shouldAutorotate {
    return NO;
}

- (void)setReturnedConfigNecessary:(NSInteger)returnedConfigNecessary {
    _returnedConfigNecessary = returnedConfigNecessary;
    if (self.loadingVC && self.outstandingConfigNecessary) [self.loadingVC.progView setProgress:((CGFloat)returnedConfigNecessary)/((CGFloat)self.outstandingConfigNecessary) animated:YES];
}

- (KPPhotoOrderController *) initWithKey:(NSString *)key {
    [DevPreferenceHelper setAppKey:key];
    [self.mixpanel track:@"partner_key" properties:[NSDictionary dictionaryWithObjects:@[key] forKeys:@[@"key"]]];
    self.showSelect = NO;
    self.isLoading = NO;
    return [self baseInit:@[]];
}

- (KPPhotoOrderController *) initWithKey:(NSString *)key andImages:(NSArray *)images {
    [DevPreferenceHelper setAppKey:key];
    [self.mixpanel track:@"partner_key" properties:[NSDictionary dictionaryWithObjects:@[key] forKeys:@[@"key"]]];
    self.showSelect = NO;
    self.isLoading = NO;
    return [self baseInit:images];
}

- (void) queueImages:(NSArray *)images {
    [self.queuedImages addObjectsFromArray:images];
    
    if ([self.queuedImages count] >= PHOTO_THRESHOLD) {
        self.showSelect = YES;
    }
}

- (void) prepareImages {
    BOOL configDone = [self checkConfigDownloaded];
    [self.incomingImages addObjectsFromArray:self.queuedImages];
    
    if (configDone) {
        if ([self.incomingImages count] < PHOTO_THRESHOLD) {
            [self processNewImages];
        } else {
            [self moveToNextViewIfReady];
        }
    } else {
        [self launchAsyncConfig];
    }

}

- (void) addImages:(NSArray *)images {
    [self.incomingImages addObjectsFromArray:images];
    
    if ([self.incomingImages count] >= PHOTO_THRESHOLD) {
        self.showSelect = YES;
    }
    
    [self prepareImages];
}

- (void) clearPendingImages {
    [self.incomingImages removeAllObjects];
}

- (NSUInteger) countOfImagesInCart {
    return [self.orderManager countOfOrders];
}

- (void) setBorderDisabled:(BOOL)disabled {
    [InterfacePreferenceHelper setBorderDisabled:disabled];
}

- (void) preRegisterUserWithEmail:(NSString *)email {
    [self preRegisterUserWithEmail:email andName:@"Kindred Prints family member"];
}
- (void) preRegisterUserWithEmail:(NSString *)email andName:(NSString *)name {
    UserObject *newUser = [UserPreferenceHelper getUserObject];
    if ([newUser.uId isEqualToString:USER_VALUE_NONE]) {
        [self.mixpanel track:@"preregister_email"];
        newUser = [[UserObject alloc] initWithId:USER_VALUE_NONE andName:name andEmail:email andAuthKey:USER_VALUE_NONE andPaymentSaved:NO];
        [UserPreferenceHelper setUserObject:newUser];
        
        NSMutableDictionary *userPost = [[NSMutableDictionary alloc] init];
        [userPost setObject:name forKey:@"name"];
        [userPost setObject:email forKey:@"email"];
        [userPost setObject:@"ios" forKey:@"os"];
        [userPost setObject:[NSNumber numberWithBool:YES] forKey:@"sdk"];
        [userPost setObject:[NSNumber numberWithBool:NO] forKey:@"send_welcome"];
        [self.ksInterface createUser:userPost];
    }
}
-(KPPhotoOrderController *)baseInit:(NSArray *)images {
    BOOL configDone = [self checkConfigDownloaded];
    [self.incomingImages addObjectsFromArray:images];
    if (configDone) {
        if ([self.incomingImages count] < PHOTO_THRESHOLD) {
            [self processNewImages];
        } else {
            self.showSelect = YES;
        }
        return [self initCart];
    }
    else return [self initLoading];
}

- (KPPhotoOrderController *)initCart {
    self = [self initWithRootViewController:[self getNextView]];
    
    [self initNavBar];
    return self;
}

- (void) initNavBar {
    [self.navigationBar setBarStyle:UIBarStyleBlack];
    [self.navigationBar setTranslucent:NO];
    [self.navigationBar setHidden:YES];
    
    [self.navigationBar setTintColor:[UIColor whiteColor]];
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0) {
        [self.navigationBar setBarTintColor:[InterfacePreferenceHelper getColor:ColorNavBar]];
    } else {
        [self.navigationBar setBackgroundImage:[[UIImage alloc] init] forBarMetrics:UIBarMetricsDefault];
        [self.navigationBar setBackgroundColor:[InterfacePreferenceHelper getColor:ColorNavBar]];
    }
}

- (KPPhotoOrderController *)initLoading {
    self.loadingVC = [[KPLoadingScreenViewController alloc] initWithNibName:@"KPLoadingScreenViewController" bundle:nil];
    self = [self initWithRootViewController:self.loadingVC];
    [self initNavBar];

    if ([self.incomingImages count] >= PHOTO_THRESHOLD) {
        self.showSelect = YES;
    }
    
    [self launchAsyncConfig];
    
    return self;
}
- (BOOL) checkConfigDownloaded {
    self.outstandingConfigNecessary = 0;
    self.returnedConfigNecessary = 0;
    
    if ([DevPreferenceHelper needDownloadSizes])
        self.outstandingConfigNecessary++;
    if ([DevPreferenceHelper needDownloadCountries])
        self.outstandingConfigNecessary++;
    if ([DevPreferenceHelper needPartnerInfo])
        self.outstandingConfigNecessary++;
    
    return self.outstandingConfigNecessary == 0;
}

- (void) launchAsyncConfig {
    if (!self.isLoading) {
        self.isLoading = YES;

        dispatch_queue_t loaderQ = dispatch_queue_create("kp_download_queue", NULL);
        dispatch_async(loaderQ, ^{
            if ([DevPreferenceHelper needDownloadSizes]) {
                [self.ksInterface getCurrentImageSizes];
            }
            if ([DevPreferenceHelper needDownloadCountries]) {
                [self.ksInterface getCountryList];
            }
            if ([DevPreferenceHelper needPartnerInfo]) {
                [self.ksInterface getPartnerDetails];
            }
        });
    }
}

- (void)processNewImages {
    for (id image in self.incomingImages) {
        [self.orderManager addExternalImage:image];
    }
    [self.incomingImages removeAllObjects];
}

- (void) moveToNextViewIfReady {
    if (self.returnedConfigNecessary >= self.outstandingConfigNecessary) {
        self.isLoading = NO;
        [self setViewControllers:@[[self getNextView]] animated:YES];
    }
}

- (UIViewController *)getNextView {
    if (self.showSelect) {
        return [[KPPhotoSelectViewController alloc] initWithNibName:@"KPPhotoSelectViewController" andImages:self.incomingImages];
    } else {
        KPCartPageViewController *cartVC = [[KPCartPageViewController alloc] initWithNibName:@"KPCartPageViewController" bundle:nil];
        cartVC.isRootController = YES;
        return cartVC;
    }
}

#pragma mark SERVER DELEGATE
- (void)serverCallback:(NSDictionary *)returnedData {
    if (returnedData) {
        NSInteger status = [[returnedData objectForKey:kpServerStatusCode] integerValue];
        NSString *requestTag = [returnedData objectForKey:kpServerRequestTag];

        if ([requestTag isEqualToString:REQ_TAG_GET_COUNTRIES]) {
            self.returnedConfigNecessary++;
            if (status == 200) {
                NSArray *countryList = [returnedData objectForKey:@"countries"];
                NSMutableArray *filteredList = [[NSMutableArray alloc] init];
                for (int i = 0; i < [countryList count]; i++) {
                    if (![[countryList objectAtIndex:i] isEqualToString:@""]) {
                        [filteredList addObject:[countryList objectAtIndex:i]];
                    }
                }

                [DevPreferenceHelper setCountries:filteredList];
                [DevPreferenceHelper resetDownloadCountryStatus];
            } else {
                NSLog(@"Error : %@", [returnedData description]);
            }
            [self moveToNextViewIfReady];
        } else if ([requestTag isEqualToString:REQ_TAG_GET_IMAGE_SIZES]) {
            self.returnedConfigNecessary++;
            NSMutableArray *newProducts = [[NSMutableArray alloc] init];
            if (status == 200) {
                NSLog(@"prices : %@", [returnedData description]);

                NSArray *serverProducts = [returnedData objectForKey:@"prices"];
                for (NSDictionary *product in serverProducts) {
                    PrintableSize *pSize = [[PrintableSize alloc] initWithDictionary:product];
                    [newProducts addObject:pSize];
                }
                [DevPreferenceHelper setCurrentSizes:newProducts];
                if ([self.incomingImages count] < PHOTO_THRESHOLD)
                    [self processNewImages];
                [self.orderManager updateAllOrdersWithNewSizes];
                
                [DevPreferenceHelper resetSizeDownloadStatus];
                [self moveToNextViewIfReady];
            } else if (status < 0) {
                UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Internet Connection Error" message:@"Printing your images requires a stable internet connection. Please try again with better reception!" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
                [alertView show];
            } else {
                NSLog(@"Error : %@", [returnedData description]);
            }
        } else if ([requestTag isEqualToString:REQ_TAG_REGISTER]) {
            if (status == 200) {
                NSString *userId = [returnedData objectForKey:@"user_id"];
                NSString *name = [returnedData objectForKey:@"name"];
                NSString *email = [returnedData objectForKey:@"email"];
                NSString *authKey = [returnedData objectForKey:@"auth_key"];
                
                UserObject *userObj = [[UserObject alloc] initWithId:userId andName:name andEmail:email andAuthKey:authKey andPaymentSaved:NO];
                [UserPreferenceHelper setUserObject:userObj];
            }
        } else if ([requestTag isEqualToString:REQ_TAG_GET_PARTNER]) {
            self.returnedConfigNecessary++;

            if (status == 200) {
                NSDictionary *partnerObj = [returnedData objectForKey:@"partner"];
                [DevPreferenceHelper setPartnerLogoUrl:[partnerObj objectForKey:@"logo"]];
                [DevPreferenceHelper setPartnerName:[partnerObj objectForKey:@"name"]];
                [DevPreferenceHelper resetPartnerDownloadStatus];
            } else {
                NSLog(@"Error : %@", [returnedData description]);
            }
            [self moveToNextViewIfReady];
        }
    }
}

#pragma mark IMAGE MANAGER DELEGATE

- (void)imageCachedNotice:(NSString *)pid {
    self.returnedConfigNecessary++;
    [self moveToNextViewIfReady];
}

@end
