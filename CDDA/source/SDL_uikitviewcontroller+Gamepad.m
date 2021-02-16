#import <__wctype.h>
//
// Created by Аполлов Юрий Андреевич on 17.01.2021.
// Copyright (c) 2021 Аполлов Юрий Андреевич. All rights reserved.
//

@import CoreGraphics;

#import "SDL_char_utils.h"

#import "SDL_uikitviewcontroller+Gamepad.h"
#import "GamePadViewController.h"


#pragma mark - OnKeyboardHandler

@interface OnKeyboardHandler : NSObject

@property (weak, nonatomic) SDL_uikitviewcontroller* _controller;

@end

@implementation OnKeyboardHandler

+(id)initWithController:(SDL_uikitviewcontroller*)controller
{
    OnKeyboardHandler* obj = [OnKeyboardHandler new];
    obj._controller = controller;
    
    return obj;
}

-(void)onKeyboard
{
    CGSize size = self._controller.view.window.frame.size;
    size.height = size.height - self._controller.keyboardHeight;
    [self._controller resizeRootView];
    [self._controller maybeUpdateFrameTo:size];
}

@end


@interface GestureRecognizerDelegate : NSObject <UIGestureRecognizerDelegate>

+(id)initWith:(UIGestureRecognizer*)first and:(UIGestureRecognizer*)second;

@end


@implementation GestureRecognizerDelegate
{
    UIGestureRecognizer* _first;
    UIGestureRecognizer* _second;
}

+(instancetype)initWith:(UIGestureRecognizer*)first and:(UIGestureRecognizer*)second
{
    GestureRecognizerDelegate* obj = [GestureRecognizerDelegate new];
    obj->_first = first;
    obj->_second = second;
    
    return obj;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (((gestureRecognizer == self->_first) && (otherGestureRecognizer == self->_second)) || ((gestureRecognizer == self->_second) && (otherGestureRecognizer == self->_first)))
        return YES;
    else
        return NO;
}

@end

#pragma mark - SDL_uikitviewcontroller (Gamepad)

@implementation SDL_uikitviewcontroller (Gamepad)

- (void)viewDidAppear:(BOOL)animated {
    NSDictionary* appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"overlayUIEnabled"];
    [NSUserDefaults.standardUserDefaults registerDefaults:appDefaults];

    for (NSNotificationName notification in @[UIKeyboardWillShowNotification, UIKeyboardWillHideNotification, UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification])
        [self registerNotification:notification forSelector:@selector(resizeRootView)];
    [self registerNotification:NSUserDefaultsDidChangeNotification forSelector:@selector(maybeToggleUI)];

    [self resizeRootView];
    [self maybeToggleUI];
    [self addRecognizers];
}

// determined empirically, on lesser sizes main menu run away screaming
static CGSize _minSize = {632, 368};

- (void)resizeRootView
{
    UIView* view = self.view;
    CGRect viewFrame = view.frame;
    UIWindow* window = UIApplication.sharedApplication.keyWindow;

    if (@available(iOS 11.0, *)) {
        UIEdgeInsets insets = window.safeAreaInsets;

        viewFrame.origin.x = insets.left;
        viewFrame.size.width = window.frame.size.width - insets.right - insets.left;
    }
    
    CGFloat keyboardLessHeight = window.frame.size.height - self.keyboardHeight;
    
    if (keyboardLessHeight >= _minSize.height)
    {
        viewFrame.size.height = keyboardLessHeight;
    }
    view.frame = viewFrame;
}

- (void)maybeToggleUI
{
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"overlayUIEnabled"])
    {
        if (!_gamepadViewController)
        {
            [self hideKeyboard];
            _gamepadViewController = [[UIStoryboard storyboardWithName:@"UIControls" bundle:nil] instantiateInitialViewController];
            [self.view addSubview:_gamepadViewController.view];

            _onKeyboardHandler = [OnKeyboardHandler initWithController:self];
            for (NSNotificationName notification in @[UIKeyboardWillShowNotification, UIKeyboardWillHideNotification]) {
                [[NSNotificationCenter defaultCenter] addObserver:_onKeyboardHandler selector:@selector(onKeyboard) name:notification object:nil];
            }
        }
    } else if (_gamepadViewController) {
        [self hideKeyboard];
        [_gamepadViewController.view removeFromSuperview];
        _gamepadViewController = nil;
        for (NSNotificationName notification in @[UIKeyboardWillShowNotification, UIKeyboardWillHideNotification]) {
            [[NSNotificationCenter defaultCenter] removeObserver:_onKeyboardHandler name:notification object:nil];
        }
        _onKeyboardHandler = nil;
    }
}

OnKeyboardHandler* _onKeyboardHandler;

- (void)registerNotification:(NSNotificationName)notification forSelector:(SEL)selector
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:selector name:notification object:nil];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [self maybeUpdateFrameTo:size];
}

- (void)maybeUpdateFrameTo:(CGSize)size {
    if (_gamepadViewController)
    {
        CGRect frame = _gamepadViewController.view.frame;
        frame.size = size;
        _gamepadViewController.view.frame = frame;
    }
}

GamePadViewController* _gamepadViewController;
@dynamic keyboardHeight;


#pragma mark - Gestures

-(void)addRecognizers
{
    UISwipeGestureRecognizer* showKeyboardGR = [UISwipeGestureRecognizer new];
    showKeyboardGR.direction = UISwipeGestureRecognizerDirectionUp;
    showKeyboardGR.delaysTouchesBegan = YES;
    [showKeyboardGR addTarget:self action:@selector(showKeyboard)];
    
    UISwipeGestureRecognizer* hideKeyboardGR = [UISwipeGestureRecognizer new];
    hideKeyboardGR.direction = UISwipeGestureRecognizerDirectionDown;
    hideKeyboardGR.delaysTouchesBegan = YES;
    [hideKeyboardGR addTarget:self action:@selector(hideKeyboard)];
    
    UIPanGestureRecognizer* panViewGR = [UIPanGestureRecognizer new];
    panViewGR.minimumNumberOfTouches = 2;
    [panViewGR addTarget:self action:@selector(panView:)];
    
    UIPinchGestureRecognizer* zoomGR = [UIPinchGestureRecognizer new];
    [zoomGR addTarget:self action:@selector(zoom:)];
    _gestureRecognizerDelegate = [GestureRecognizerDelegate initWith:panViewGR and:zoomGR];
    zoomGR.delegate = _gestureRecognizerDelegate;

    for (UIGestureRecognizer* recognizer in @[showKeyboardGR, hideKeyboardGR, panViewGR, zoomGR])
        [self.view addGestureRecognizer:recognizer];
}

GestureRecognizerDelegate* _gestureRecognizerDelegate;


#pragma mark - Zoom handling

-(void)zoom:(UIPinchGestureRecognizer*)sender
{
    if ((sender.scale > _minScale) || (sender.scale < _maxScale))
    {
        NSString* text;
        int multiplier;
        if (sender.scale > 1)
        {
            text = @"z";
            multiplier = (sender.scale - 1) / _zoomingPrecision;
        }
        else
        {
            text = @"Z";
            multiplier = (1 - sender.scale) / _zoomingPrecision;
        }
        sender.scale = 1;
        
        for (int i=0; i < multiplier; i++)
            SDL_send_text_event(text);
    }
}

const float _zoomingPrecision = 0.25;
const float _minScale = 1 + _zoomingPrecision;
const float _maxScale = 1 - _zoomingPrecision;



#pragma mark - Pan view

CGPoint lastPanningLocation;

-(void)panView:(UIPanGestureRecognizer*)sender
{
    if ((sender.state == UIGestureRecognizerStateChanged) || ( sender.state == UIGestureRecognizerStateEnded))
    {
        CGPoint currentLocation = [sender translationInView:sender.view];
        CGPoint movement = {.x=(currentLocation.x - lastPanningLocation.x), .y=(currentLocation.y - lastPanningLocation.y)};
        float xAbs = fabs(movement.x);
        float yAbs = fabs(movement.y);
        
        if ((xAbs > _panningPrecision) || (yAbs > _panningPrecision))
        {
            NSString* text;
            int multiplier;
            if (xAbs > yAbs)
            {
                multiplier = xAbs / _panningPrecision;
                if (movement.x > 0)
                    text = @"H";
                else
                    text = @"L";
            }
            else
            {
                multiplier = yAbs / _panningPrecision;
                if (movement.y > 0)
                    text = @"K";
                else
                    text = @"J";
            }
            for (int i=0; i < multiplier; i++)
                SDL_send_text_event(text);
            lastPanningLocation = currentLocation;
        }
    }
    if ((sender.state == UIGestureRecognizerStateCancelled) || ( sender.state == UIGestureRecognizerStateEnded))
    {
        lastPanningLocation = CGPointZero;
    }
}

const int _panningPrecision = 10;

@end
