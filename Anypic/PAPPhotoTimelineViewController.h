//
//  PAPPhotoTimelineViewController.h
//  Anypic
//
//  Created by Héctor Ramos on 5/3/12.
//  Copyright (c) 2013 Parse. All rights reserved.
//

#import "PAPPhotoHeaderView.h"

// extends PFQueryTableViewController, which provides one-to-one mapping between
// UITableViewCell cells and PFObjects
@interface PAPPhotoTimelineViewController : PFQueryTableViewController <PAPPhotoHeaderViewDelegate>

- (PAPPhotoHeaderView *)dequeueReusableSectionHeaderView;

@end
