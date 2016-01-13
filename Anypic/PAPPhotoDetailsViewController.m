//
//  PAPPhotoDetailViewController.m
//  Anypic
//
//  Created by Mattieu Gamache-Asselin on 5/15/12.
//  Copyright (c) 2013 Parse. All rights reserved.
//

#import "PAPPhotoDetailsViewController.h"
#import "PAPBaseTextCell.h"
#import "PAPActivityCell.h"
#import "PAPPhotoDetailsFooterView.h"
#import "PAPConstants.h"
#import "PAPAccountViewController.h"
#import "PAPLoadMoreCell.h"
#import "PAPUtility.h"
#import "MBProgressHUD.h"
#import "AppDelegate.h"

enum ActionSheetTags {
    MainActionSheetTag = 0,
    ConfirmDeleteActionSheetTag = 1
};

@interface PAPPhotoDetailsViewController ()
@property (nonatomic, strong) UITextField *commentTextField;
@property (nonatomic, strong) PAPPhotoDetailsHeaderView *headerView;
@property (nonatomic, assign) BOOL likersQueryInProgress;
@end

static const CGFloat kPAPCellInsetWidth = 0.0f;

@implementation PAPPhotoDetailsViewController

@synthesize commentTextField;
@synthesize photo, headerView;

#pragma mark - Initialization

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:PAPUtilityUserLikedUnlikedPhotoCallbackFinishedNotification object:self.photo];
}

- (id)initWithPhoto:(PFObject *)aPhoto {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        // The className to query on
        self.parseClassName = kPAPActivityClassKey;

        // Whether the built-in pull-to-refresh is enabled
        self.pullToRefreshEnabled = YES;

        // Whether the built-in pagination is enabled
        self.paginationEnabled = YES;
        
        // The number of comments to show per page
        self.objectsPerPage = 30;
        
        self.photo = aPhoto;
        
        self.likersQueryInProgress = NO;
    }
    return self;
}


#pragma mark - UIViewController

- (void)viewDidLoad {
    [self.tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];

    [super viewDidLoad];
    
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LogoNavigationBar.png"]];
    
    // Set table view properties
    UIView *texturedBackgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    texturedBackgroundView.backgroundColor = [UIColor blackColor];
    self.tableView.backgroundView = texturedBackgroundView;
    
    // Set table header
    self.headerView = [[PAPPhotoDetailsHeaderView alloc] initWithFrame:[PAPPhotoDetailsHeaderView rectForView] photo:self.photo];
    self.headerView.delegate = self;
    
    self.tableView.tableHeaderView = self.headerView;
    
    // Set table footer: PAPPhotoDetailsFooterView is a small class, wrapping UITextField, set as the footer; with its delgate being the view controller
    PAPPhotoDetailsFooterView *footerView = [[PAPPhotoDetailsFooterView alloc] initWithFrame:[PAPPhotoDetailsFooterView rectForView]];
    commentTextField = footerView.commentField;
    commentTextField.delegate = self;   // set delegate
    self.tableView.tableFooterView = footerView;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(activityButtonAction:)];
    
    // Register to be notified when the keyboard will be shown to scroll the view
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userLikedOrUnlikedPhoto:) name:PAPUtilityUserLikedUnlikedPhotoCallbackFinishedNotification object:self.photo];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.headerView reloadLikeBar];
    
    // we will only hit the network if we have no cached data for this photo
    BOOL hasCachedLikers = [[PAPCache sharedCache] attributesForPhoto:self.photo] != nil;
    if (!hasCachedLikers) {
        [self loadLikers];
    }
}


#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.objects.count) { // A comment row
        PFObject *object = [self.objects objectAtIndex:indexPath.row];
        
        if (object) {
            NSString *commentString = [self.objects[indexPath.row] objectForKey:kPAPActivityContentKey];
            
            PFUser *commentAuthor = (PFUser *)[object objectForKey:kPAPActivityFromUserKey];
            
            NSString *nameString = @"";
            if (commentAuthor) {
                nameString = [commentAuthor objectForKey:kPAPUserDisplayNameKey];
            }
            
            return [PAPActivityCell heightForCellWithName:nameString contentString:commentString cellInsetWidth:kPAPCellInsetWidth];
        }
    }
    
    // The pagination row
    return 44.0f;
}


#pragma mark - PFQueryTableViewController

- (PFQuery *)queryForTable {
    PFQuery *query = [PFQuery queryWithClassName:self.parseClassName];
    [query whereKey:kPAPActivityPhotoKey equalTo:self.photo];
    [query includeKey:kPAPActivityFromUserKey]; // this provides us with the commenter's commetn and profile image
    [query whereKey:kPAPActivityTypeKey equalTo:kPAPActivityTypeComment];
    [query orderByAscending:@"createdAt"]; 

    [query setCachePolicy:kPFCachePolicyNetworkOnly];

    // If no objects are loaded in memory, we look to the cache first to fill the table
    // and then subsequently do a query against the network.
    //
    // If there is no network connection, we will hit the cache first.
        // selector just lets us access a previously designate method for use at runtime
    if (self.objects.count == 0 || ![[UIApplication sharedApplication].delegate performSelector:@selector(isParseReachable)]) {
        [query setCachePolicy:kPFCachePolicyCacheThenNetwork];
    }
    
    return query;
}

- (void)objectsDidLoad:(NSError *)error {
    [super objectsDidLoad:error];

    [self.headerView reloadLikeBar];
    [self loadLikers];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath object:(PFObject *)object {
    static NSString *cellID = @"CommentCell";

    // Try to dequeue a cell and create one if necessary
    PAPBaseTextCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[PAPBaseTextCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        cell.cellInsetWidth = kPAPCellInsetWidth;
        cell.delegate = self;
    }
    
    [cell setUser:[object objectForKey:kPAPActivityFromUserKey]];
    [cell setContentText:[object objectForKey:kPAPActivityContentKey]];
    [cell setDate:[object createdAt]];

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForNextPageAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"NextPageDetails";
    
    PAPLoadMoreCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (cell == nil) {
        cell = [[PAPLoadMoreCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.cellInsetWidth = kPAPCellInsetWidth;
        cell.hideSeparatorTop = YES;
    }
    
    return cell;
}


#pragma mark - UITextFieldDelegate (commenting on a photo)

// this delegate method is called whenever a user adds/submits a new comment to a photo
// Outline:
//  1. Create and save PFObject
//  2. Handle the case where a photo was deleted
//  3. Send push notifications
//  4. Update the local cache
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // trim the comment text
    NSString *trimmedComment = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // if a comment actually exists, create and save the PFObject for the comment
    if (trimmedComment.length != 0 && [self.photo objectForKey:kPAPPhotoUserKey]) {
        PFObject *comment = [PFObject objectWithClassName:kPAPActivityClassKey];
        [comment setObject:trimmedComment forKey:kPAPActivityContentKey]; // Set comment text
        [comment setObject:[self.photo objectForKey:kPAPPhotoUserKey] forKey:kPAPActivityToUserKey]; // Set toUser
        [comment setObject:[PFUser currentUser] forKey:kPAPActivityFromUserKey]; // Set fromUser
        [comment setObject:kPAPActivityTypeComment forKey:kPAPActivityTypeKey];
        [comment setObject:self.photo forKey:kPAPActivityPhotoKey];
        
        // permissions: user read/write, public read
        PFACL *ACL = [PFACL ACLWithUser:[PFUser currentUser]];
        [ACL setPublicReadAccess:YES];
        [ACL setWriteAccess:YES forUser:[self.photo objectForKey:kPAPPhotoUserKey]];    // remember, self.photo is set on init, and this view
        comment.ACL = ACL;                                                              // represents a single photo being viewed

        // cache the photo comment count. We do this before saving the photo because we use
        // "saveEventually" method, which we can safely assume won't have errors
        [[PAPCache sharedCache] incrementCommentCountForPhoto:self.photo];
        
        // Show HUD view: a loading heads-up display to show we are saving
        [MBProgressHUD showHUDAddedTo:self.view.superview animated:YES];
        
        // start a NSTimer to give it a chance to
        // If more than 5 seconds pass since we post a comment, stop waiting for the server to respond
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:5.0f target:self selector:@selector(handleCommentTimeout:) userInfo:@{@"comment": comment} repeats:NO];

        // start saving now; if takes longer than 5 seconds, NSTimer activates and tells user
        // comment will be saved eventually
        [comment saveEventually:^(BOOL succeeded, NSError *error) {     // this block is called a completion block: a lambda called upon method completion
            [timer invalidate]; // ensures timer alert does not display
            
            // if owner of image deleted the image, but the current user's app hasn't updated to reflect this, then
            // the object won't be found and we must cancel the process and alert the user that the photo is no longer available.
            // Finally, we need to also reset our changes to the cache, since we won't be storing anything about this photo in the cache
            if (error && error.code == kPFErrorObjectNotFound) {
                [[PAPCache sharedCache] decrementCommentCountForPhoto:self.photo];
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Could not post comment", nil) message:NSLocalizedString(@"This photo is no longer available", nil) delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
                [alert show];
                [self.navigationController popViewControllerAnimated:YES];
            }
            
            // if the comment saved successfully, send a notification to the user about comment count
            [[NSNotificationCenter defaultCenter] postNotificationName:PAPPhotoDetailsViewControllerUserCommentedOnPhotoNotification object:self.photo userInfo:@{@"comments": @(self.objects.count + 1)}];
            
            // remove the progress hud
            [MBProgressHUD hideHUDForView:self.view.superview animated:YES];
            // reload the table
            [self loadObjects];
        }];
    }
    
    [textField setText:@""];                    // clear text, whether or not save succeeded
    return [textField resignFirstResponder];    // clear the keyboard
}


#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == MainActionSheetTag) {
        if ([actionSheet destructiveButtonIndex] == buttonIndex) {
            // prompt to delete
            UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Are you sure you want to delete this photo?", nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) destructiveButtonTitle:NSLocalizedString(@"Yes, delete photo", nil) otherButtonTitles:nil];
            actionSheet.tag = ConfirmDeleteActionSheetTag;
            [actionSheet showFromTabBar:self.tabBarController.tabBar];
        } else {
            [self activityButtonAction:actionSheet];
        }
    } else if (actionSheet.tag == ConfirmDeleteActionSheetTag) {
        if ([actionSheet destructiveButtonIndex] == buttonIndex) {
            
            [self shouldDeletePhoto];
        }
    }
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [commentTextField resignFirstResponder];
}


#pragma mark - PAPBaseTextCellDelegate

- (void)cell:(PAPBaseTextCell *)cellView didTapUserButton:(PFUser *)aUser {
    [self shouldPresentAccountViewForUser:aUser];
}


#pragma mark - PAPPhotoDetailsHeaderViewDelegate

-(void)photoDetailsHeaderView:(PAPPhotoDetailsHeaderView *)headerView didTapUserButton:(UIButton *)button user:(PFUser *)user {
    [self shouldPresentAccountViewForUser:user];
}

- (void)actionButtonAction:(id)sender {
    UIActionSheet *actionSheet = [[UIActionSheet alloc] init];
    actionSheet.delegate = self;
    actionSheet.tag = MainActionSheetTag;
    actionSheet.destructiveButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Delete Photo", nil)];
    if (NSClassFromString(@"UIActivityViewController")) {
        [actionSheet addButtonWithTitle:NSLocalizedString(@"Share Photo", nil)];
    }
    actionSheet.cancelButtonIndex = [actionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [actionSheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)activityButtonAction:(id)sender {
    if ([[self.photo objectForKey:kPAPPhotoPictureKey] isDataAvailable]) {
        [self showShareSheet];
    } else {
        [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        [[self.photo objectForKey:kPAPPhotoPictureKey] getDataInBackgroundWithBlock:^(NSData *data, NSError *error) {
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            if (!error) {
                [self showShareSheet];
            }
        }];
    }
}


#pragma mark - ()

- (void)showShareSheet {
    [[self.photo objectForKey:kPAPPhotoPictureKey] getDataInBackgroundWithBlock:^(NSData *data, NSError *error) {
        if (!error) {
            NSMutableArray *activityItems = [NSMutableArray arrayWithCapacity:3];
                        
            // Prefill caption if this is the original poster of the photo, and then only if they added a caption initially.
            if ([[[PFUser currentUser] objectId] isEqualToString:[[self.photo objectForKey:kPAPPhotoUserKey] objectId]] && [self.objects count] > 0) {
                PFObject *firstActivity = self.objects[0];
                if ([[[firstActivity objectForKey:kPAPActivityFromUserKey] objectId] isEqualToString:[[self.photo objectForKey:kPAPPhotoUserKey] objectId]]) {
                    NSString *commentString = [firstActivity objectForKey:kPAPActivityContentKey];
                    [activityItems addObject:commentString];
                }
            }
            
            [activityItems addObject:[UIImage imageWithData:data]];
            [activityItems addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://anypic.org/#pic/%@", self.photo.objectId]]];
            
            UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:nil];
            [self.navigationController presentViewController:activityViewController animated:YES completion:nil];
        }
    }];
}

- (void)handleCommentTimeout:(NSTimer *)aTimer {
    [MBProgressHUD hideHUDForView:self.view.superview animated:YES];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"New Comment", nil) message:NSLocalizedString(@"Your comment will be posted next time there is an Internet connection.", nil)  delegate:nil cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Dismiss", nil), nil];
    [alert show];
}

- (void)shouldPresentAccountViewForUser:(PFUser *)user {
    PAPAccountViewController *accountViewController = [[PAPAccountViewController alloc] initWithStyle:UITableViewStylePlain];
    NSLog(@"Presenting account view controller with user: %@", user);
    [accountViewController setUser:user];
    [self.navigationController pushViewController:accountViewController animated:YES];
}

- (void)backButtonAction:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)userLikedOrUnlikedPhoto:(NSNotification *)note {
    [self.headerView reloadLikeBar];
}

- (void)keyboardWillShow:(NSNotification*)note {
    // Scroll the view to the comment text box
    NSDictionary* info = [note userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    [self.tableView setContentOffset:CGPointMake(0.0f, self.tableView.contentSize.height-kbSize.height) animated:YES];
}

- (void)loadLikers {
    if (self.likersQueryInProgress) {
        return;
    }

    self.likersQueryInProgress = YES;
    PFQuery *query = [PAPUtility queryForActivitiesOnPhoto:photo cachePolicy:kPFCachePolicyNetworkOnly];
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        self.likersQueryInProgress = NO;
        if (error) {
            [self.headerView reloadLikeBar];
            return;
        }
        
        NSMutableArray *likers = [NSMutableArray array];
        NSMutableArray *commenters = [NSMutableArray array];
        
        BOOL isLikedByCurrentUser = NO;
        
        for (PFObject *activity in objects) {
            if ([[activity objectForKey:kPAPActivityTypeKey] isEqualToString:kPAPActivityTypeLike] && [activity objectForKey:kPAPActivityFromUserKey]) {
                [likers addObject:[activity objectForKey:kPAPActivityFromUserKey]];
            } else if ([[activity objectForKey:kPAPActivityTypeKey] isEqualToString:kPAPActivityTypeComment] && [activity objectForKey:kPAPActivityFromUserKey]) {
                [commenters addObject:[activity objectForKey:kPAPActivityFromUserKey]];
            }
            
            if ([[[activity objectForKey:kPAPActivityFromUserKey] objectId] isEqualToString:[[PFUser currentUser] objectId]]) {
                if ([[activity objectForKey:kPAPActivityTypeKey] isEqualToString:kPAPActivityTypeLike]) {
                    isLikedByCurrentUser = YES;
                }
            }
        }
        
        [[PAPCache sharedCache] setAttributesForPhoto:photo likers:likers commenters:commenters likedByCurrentUser:isLikedByCurrentUser];
        [self.headerView reloadLikeBar];
    }];
}

- (BOOL)currentUserOwnsPhoto {
    return [[[self.photo objectForKey:kPAPPhotoUserKey] objectId] isEqualToString:[[PFUser currentUser] objectId]];
}

- (void)shouldDeletePhoto {
    // Delete all activites related to this photo
    PFQuery *query = [PFQuery queryWithClassName:kPAPActivityClassKey];
    [query whereKey:kPAPActivityPhotoKey equalTo:self.photo];
    [query findObjectsInBackgroundWithBlock:^(NSArray *activities, NSError *error) {
        if (!error) {
            for (PFObject *activity in activities) {
                [activity deleteEventually];
            }
        }
        
        // Delete photo
        [self.photo deleteEventually];
    }];
    [[NSNotificationCenter defaultCenter] postNotificationName:PAPPhotoDetailsViewControllerUserDeletedPhotoNotification object:[self.photo objectId]];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
