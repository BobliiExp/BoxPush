//
//  ViewController.m
//  BoxPush
//
//  Created by Bob Lee on 2017/7/31.
//  Copyright © 2017年 Anyfish. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#define SCREEN_WIDTH_6P     414.0f /// 6+尺寸部分适配需要用到
#define kPadding_BottomBar_H                30.0f       // 全屏等界面的底部操作按钮距离左右屏幕边距
#define kPadding_BottomBar_V                20.0f       // 全屏等界面的底部操作按钮距离底部屏幕边距

typedef NS_ENUM(NSInteger,  AFFBoxSubType) {
    EBox_None,      ///< 空白
    EBox_Wall,      ///< 墙
    EBox_Box,       ///< 箱子
    EBox_Target,    ///< 目标
    EBox_Road,      ///< 路
    EBox_Robot,     ///< 机器人
    EBox_RobotT,     ///< 机器人在目标上
    EBox_BoxT,     ///< 目标处的箱子，可能初始化就在目标上了
};

static void * codeSubType = (void *)@"subType";

@interface UIView (Bob)

@property (nonatomic, assign) AFFBoxSubType sType;

@end

@implementation UIView (Bob)

- (AFFBoxSubType)sType {
    return ((NSNumber*)objc_getAssociatedObject(self, codeSubType)).integerValue;
}

- (void)setSType:(AFFBoxSubType)sType {
    
    objc_setAssociatedObject(self, codeSubType, @(sType), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end


@interface ViewController () <AVAudioPlayerDelegate> {
    BOOL finish;
    CGRect frameGesture; // 手势有效范围
    
    BOOL isMoveing; // 是否正在移动中
    UIPanGestureRecognizer *panGesture;
    
    NSMutableArray *mArrTrace; // 还原数组 @[{@"Box":@[@(tag),@(scope对应索引)], @"Robot":@[@(tag)]}]
    NSMutableArray *mArrOrg;
    BOOL hasEnjoy;
    NSInteger timesOfBox;
    
    AVAudioPlayer *avAudioPlayer;
}

@property (nonatomic, weak) UIImageView *imgVRobot;    ///< 机器人
@property (nonatomic, weak) UILabel *labjoy;
@property (nonatomic, strong) NSMutableArray *mArrData, *mArrScope, *mArrFilted;

@end

@implementation ViewController

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
    [avAudioPlayer stop];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
    if(self.mArrData.count>0)
        [avAudioPlayer play];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    
    [self setup];
    [self setupData];
    [self setupSound];
}

- (void)setup {
    // 背景
    UIImageView *imgV = [[UIImageView alloc] initWithFrame:self.view.bounds];
    imgV.image = [UIImage imageNamed:@"ic_gm_game_boxbg"];
    [self.view addSubview:imgV];
    
    // 底部操作栏
    NSArray *opr = @[@"ic_gm_game_box_close", @"ic_gm_game_box_back", @"ic_gm_game_box_reset"];
    
    CGFloat widthSc = CGRectGetWidth(self.view.frame);
    CGFloat heightSc = CGRectGetHeight(self.view.frame);
    
    CGFloat width = 40;
    CGFloat padding = (widthSc- MIN(widthSc,SCREEN_WIDTH_6P))/2+kPadding_BottomBar_H;
    CGFloat widthContent = widthSc-padding*2;
    CGFloat padding1 = (widthContent-width*opr.count)/(opr.count-1);
    
    for(NSInteger i=0; i<opr.count; i++){
        NSString *img = [opr objectAtIndex:i];
        UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(padding+i*(width+padding1), heightSc-width-kPadding_BottomBar_V, width, width)];
        [btn setImage:[UIImage imageNamed:img] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(btnClicked:) forControlEvents:UIControlEventTouchUpInside];
        btn.tag = 199000000+i;
        [self.view addSubview:btn];
    }
    
}

// 用字符表示地图的元素。W表示墙，M表示人，E表示外空白，空白字符表示内空白，F表示目的地，X表示放在目的地的箱子，B表示箱子
- (void)setupData {
    [avAudioPlayer play];
    
    mArrTrace = [NSMutableArray array]; // 轨迹
    self.mArrFilted = [NSMutableArray array]; // 箱子
    self.mArrScope = [NSMutableArray array]; // 箱子对应views
    self.mArrData = [NSMutableArray array]; // 二维数组装在地图每个方格
    
    // 数据类型，墙、箱子、目标、地、机器人
    [self.mArrData addObject:@[@(EBox_None),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_None)]];
    [self.mArrData addObject:@[@(EBox_Wall),@(EBox_Wall),@(EBox_Road),@(EBox_Road),@(EBox_Road),@(EBox_Road),@(EBox_Wall),@(EBox_None)]];
    [self.mArrData addObject:@[@(EBox_Wall),@(EBox_Wall),@(EBox_Box),@(EBox_Road),@(EBox_Road),@(EBox_Road),@(EBox_Wall),@(EBox_None)]];
    [self.mArrData addObject:@[@(EBox_Wall),@(EBox_Road),@(EBox_Road),@(EBox_Box),@(EBox_Robot),@(EBox_Road),@(EBox_Road),@(EBox_Wall)]];
    [self.mArrData addObject:@[@(EBox_Wall),@(EBox_Road),@(EBox_Road),@(EBox_Road),@(EBox_Road),@(EBox_Road),@(EBox_Target),@(EBox_Wall)]];
    [self.mArrData addObject:@[@(EBox_Wall),@(EBox_Wall),@(EBox_Target),@(EBox_Road),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall)]];
    [self.mArrData addObject:@[@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_Wall),@(EBox_None),@(EBox_None),@(EBox_None),@(EBox_None)]];
    
    timesOfBox = self.mArrData.count * ((NSArray*)[self.mArrData firstObject]).count;
    CGFloat heigheBottom = 40+kPadding_BottomBar_V;
    // 数据类型，墙、箱子、目标、地、机器人
    
    CGFloat width = 33;
    CGFloat height = 36;
    CGFloat padding = 15;
    CGFloat y = 0;
    
    CGFloat SCREEN_WIDTH = CGRectGetWidth(self.view.frame);
    CGFloat SCREEN_HEIGHT = CGRectGetHeight(self.view.frame);
    
    CGFloat widthT = width*((NSArray*)[self.mArrData firstObject]).count;
    CGFloat heightT = height*self.mArrData.count;
    CGFloat heightMax = SCREEN_HEIGHT-y-heigheBottom;
    
    if(heightT>(heightMax-30*2)){
        heightT = (heightMax-30*2);
        height = heightT/self.mArrData.count;
        width = width*height/36;
        
        widthT = width*((NSArray*)[self.mArrData firstObject]).count;
        if(widthT>(SCREEN_WIDTH-padding*2)){
            widthT = (SCREEN_WIDTH-padding*2);
            
            CGFloat temp = width;
            width = widthT/((NSArray*)[self.mArrData firstObject]).count;
            height = height*width/temp;
        }else {
            padding = (SCREEN_WIDTH-widthT)/2;
        }
        
    }else {
        if(widthT>(SCREEN_WIDTH-padding*2)){
            widthT = (SCREEN_WIDTH-padding*2);
            width = widthT/((NSArray*)[self.mArrData firstObject]).count;
            height = height*width/33;
            heightT = height*self.mArrData.count;
        }else {
            padding = (SCREEN_WIDTH-widthT)/2;
        }
    }
    
    frameGesture = CGRectMake(0, y, SCREEN_WIDTH, SCREEN_HEIGHT-y-heigheBottom);
    
    CGFloat x=padding;
    y = y + (SCREEN_HEIGHT-y-heightT-heigheBottom)/2;
    
    for(NSInteger row=0; row<self.mArrData.count; row++){
        NSArray *arr = [self.mArrData objectAtIndex:row];
        
        for(NSInteger column=0; column<arr.count; column++){
            NSNumber *number = [arr objectAtIndex:column];
            
            AFFBoxSubType sType = number.integerValue;
            
            if(sType != EBox_None){
                if(sType == EBox_BoxT){
                    [self.mArrFilted addObject:@[@(EBox_Box), @(row), @(column)]];
                    sType = EBox_Target;
                }else if(sType == EBox_Box){
                    [self.mArrFilted addObject:@[@(EBox_Box), @(row), @(column)]];
                    sType = EBox_Road;
                }else if(sType == EBox_Robot){
                    [self.mArrFilted addObject:@[@(EBox_Robot), @(row), @(column)]];
                    sType = EBox_Road;
                }else if(sType == EBox_RobotT){
                    [self.mArrFilted addObject:@[@(EBox_Robot), @(row), @(column)]];
                    sType = EBox_Target;
                }
                
                UIImageView *imgV = [[UIImageView alloc] initWithFrame:CGRectMake(x, y, width, height)];
                imgV.image = [UIImage imageNamed:[self getSubImage:sType]];
                imgV.sType = sType;
                imgV.tag = row*100+column;
                [self.view addSubview:imgV];
                
                if(sType != EBox_Wall &&
                   sType != EBox_None){
                    imgV.userInteractionEnabled = YES;
                    [imgV addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleViewTapChanged:)]];
                }
            }
            
            x+=width;
        }
        
        y+=height;
        x=padding;
    }
    
    [self setupBox];
    
    self.view.userInteractionEnabled = YES;
    
    // 添加手势
    UISwipeGestureRecognizer *swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipeGesture];
    
    swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:swipeGesture];
    
    swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:swipeGesture];
    
    swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeGesture:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:swipeGesture];
    
    panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    [self.view addGestureRecognizer:panGesture];
}

- (void)setupBox {
    finish = NO;
    
    if(self.mArrScope.count>0) {
        // 清理
        for(UIView *view in self.mArrScope){
            [view removeFromSuperview];
        }
        
        [self.mArrScope removeAllObjects];
        
        [self.imgVRobot removeFromSuperview];
        
        [mArrTrace removeAllObjects];
    }
    
    for(NSArray *arr in self.mArrFilted){
        AFFBoxSubType sType = (AFFBoxSubType)(((NSNumber*)[arr firstObject]).charValue);
        NSInteger row = ((NSNumber*)[arr objectAtIndex:1]).integerValue;
        NSInteger column = ((NSNumber*)[arr objectAtIndex:2]).integerValue;
        UIView *view = [self.view viewWithTag:row*100+column];
        UIImageView *imgV = [[UIImageView alloc] initWithFrame:view.frame];
        imgV.image = [UIImage imageNamed:[self getSubImage:sType]];
        imgV.tag = view.tag*timesOfBox;
        [self.view addSubview:imgV];
        
        imgV.sType = sType;
        
        imgV.userInteractionEnabled = YES;
        [imgV addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleViewTapChanged:)]];
        
        if(sType == EBox_Box){
            [self.mArrScope addObject:imgV];
            
            CGFloat widthC = 16;
            UIImageView *imgVx = [[UIImageView alloc] initWithFrame:CGRectMake((CGRectGetWidth(imgV.frame)-widthC)/2, (CGRectGetHeight(imgV.frame)-widthC)/2, widthC, widthC)];
            imgVx.image = [UIImage imageNamed:@"ic_gm_game_box_check"];
            imgVx.userInteractionEnabled = NO;
            imgVx.tag = 199000010;
            [imgV addSubview:imgVx];
            
            // 检查是否已经在目标上
            UIView *temp = [self.view viewWithTag:imgV.tag/timesOfBox];
            AFFBoxSubType st = temp.sType;
            imgVx.alpha = (temp&&st==EBox_Target)?1:0;
        }
        
        if(sType == EBox_Robot){
            self.imgVRobot = imgV;
        }
    }
}

- (void)setupSound {
    if(avAudioPlayer)return;
    
    NSString *string = [[NSBundle mainBundle] pathForResource:@"ring_game_boxbg" ofType:@"mp3"];
    //把音频文件转换成url格式
    NSURL *url = [NSURL fileURLWithPath:string];
    //初始化音频类 并且添加播放文件
    NSError *error;
    avAudioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    if(error){
        avAudioPlayer = nil;
        return;
    }
    
    //设置代理
    avAudioPlayer.delegate = self;
    
    //设置音乐播放次数  -1为一直循环
    avAudioPlayer.numberOfLoops = -1;
    
    //预播放
    [avAudioPlayer prepareToPlay];
}

/**
 * 被点击的view与机器人的位置关系判断是否可以操作
 1.任意方向如果点击的是箱子，箱子与机器人方向向量前有路就可以前进；箱子进入目标点显示确认图标；箱子前面还有箱子不能前进
 2.点击了相邻的路，机器人前进
 3.注意箱子，机器人的tag是会随着移动改变
 */
- (void)walkForward:(UIView*)viewClicked {
    AFFBoxSubType sType = viewClicked.sType;
    if(sType == EBox_Wall ||
       sType == EBox_None ||
       sType == EBox_Robot ||
       finish ||
       isMoveing){
        return;
    }
    
    isMoveing = YES;
    
    NSInteger delta = 1;
    if(sType == EBox_Box){
        delta = timesOfBox;
    }
    
    // 点击位置
    NSInteger row = (viewClicked.tag/delta)/100;
    NSInteger column = (viewClicked.tag/delta)%100;
    
    // 机器人位置
    NSInteger row1 = (self.imgVRobot.tag/timesOfBox)/100;
    NSInteger column1 = (self.imgVRobot.tag/timesOfBox)%100;
    
    // 移动的下一个位置
    NSInteger row2 = -1;
    NSInteger column2 = -1;
    
    UIView *viewF = nil; // 前进的下一个目标
    
    if(row==row1){
        // 是水平相邻，跳跃点击不生效（目前考虑)
        if(labs(column-column1)==1){
            row2 = row;
            column2 = column > column1 ? (column+1) : (sType==EBox_Box ? column-1 : column1-1); // 像右或者左 (向左要考虑点击的是箱子，则需要再往左移动一格）
        }
    }else if(column==column1){
        if(labs(row-row1)==1){
            row2 = row > row1 ? (row+1) : (sType == EBox_Box ? row-1 : row1-1); // 向下或者上 (向上要考虑点击的是箱子，则需要再往上移动一格）
            column2 = column;
        }
    }
    
    int handleCount = 0;
    
    if(row2>=0 && column2>=0){
        // 这里分两种情况
        // 1.点击的是路，直接前进
        if(sType == EBox_Road ||
           sType == EBox_Target){
            [mArrTrace addObject:@{@"Robot":@[@(self.imgVRobot.tag/timesOfBox)]}];
            [self walkToView:viewClicked fromView:self.imgVRobot];
            handleCount++;
            [ViewController playSoundWithName:@"ring_assets_cate_clicked" type:@"wav"];
        }else {
            // 2.点击的只可能是箱子
            UIView *viewUBox = [self.view viewWithTag:viewClicked.tag/timesOfBox];
            viewF = [self.view viewWithTag:100*row2+column2];
            
            // 特殊情况，判断是否有箱子在viewF上
            UIView *viewO = [self.view viewWithTag:viewF.tag*timesOfBox];
            
            // 只有前面是路或者目标才能向前
            AFFBoxSubType sType1 = viewF.sType;
            if((sType1 == EBox_Target ||
                sType1 == EBox_Road) && viewO==nil){
                [mArrTrace addObject:@{@"Box":@[@(viewClicked.tag/timesOfBox), @([self.mArrScope indexOfObject:viewClicked])], @"Robot":@[@(self.imgVRobot.tag/timesOfBox)]}];
                
                [self walkToView:viewF fromView:viewClicked];
                handleCount++;
                [self walkToView:viewUBox fromView:self.imgVRobot];
                handleCount++;
                [ViewController playSoundWithName:@"ring_game_boxpush" type:@"mp3"];
            }
        }
    }
    
    if(handleCount==0){
        isMoveing=NO;
    }else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(handleCount*0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            isMoveing = NO;
        });
    }
}

- (void)walkToView:(UIView*)view fromView:(UIView*)viewf {
    viewf.tag = view.tag*timesOfBox;
    
    CGRect frame = view.frame;
    view.userInteractionEnabled = NO;
    
    AFFBoxSubType sTypef = viewf.sType;
    UIView *sub = nil;
    if(sTypef==EBox_Box){
        sub = [viewf viewWithTag:199000010];
        sub.alpha = 0;
    }
    
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        viewf.frame = frame;
    } completion:^(BOOL finished) {
        view.userInteractionEnabled = YES;
        
        AFFBoxSubType sType = view.sType;
        if(sType==EBox_Target && sTypef == EBox_Box){
            UIView *sub = [viewf viewWithTag:199000010];
            sub.alpha = 1.0;
            
            [ViewController playSoundWithName:@"ring_work_clock_succed" type:@"wav"];
            [UIView animateWithDuration:0.15
                                  delay:0
                                options:UIViewAnimationOptionCurveLinear
                             animations:^{
                                 sub.transform = CGAffineTransformScale(sub.transform, 1.4, 1.4);
                                 
                             }completion:^(BOOL finished) {
                                 [UIView animateWithDuration:0.15
                                                       delay:0.05
                                                     options:UIViewAnimationOptionCurveLinear
                                                  animations:^{
                                                      sub.transform = CGAffineTransformIdentity;
                                                  }completion:^(BOOL finished) {
                                                      [self checkGame];
                                                  }];
                             }];
        }
    }];
}

- (NSString*)getSubImage:(AFFBoxSubType)type {
    switch (type) {
        case EBox_Box: { return @"ic_gm_game_box_box"; } break;
        case EBox_Road: { return @"ic_gm_game_box_road"; } break;
        case EBox_Wall: { return @"ic_gm_game_box_wall"; } break;
        case EBox_Robot: { return @"ic_gm_game_box_robot"; } break;
        case EBox_Target: { return @"ic_gm_game_box_target"; } break;
            
        default: { return nil; } break;
    }
}

- (void)checkGame {
    finish = YES;
    for(UIImageView *imgV in self.mArrScope){
        UIView *view = [imgV viewWithTag:199000010];
        finish = finish && view.alpha==1;
    }
    
    if(finish){
        [ViewController playSoundWithName:@"ring_radio_guesssuccess" type:@"amr"];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupBox];
        });
    }
}

- (void)walkBack {
    if(mArrTrace.count>0){
        NSDictionary *dic = [mArrTrace lastObject];
        NSArray *arr = [dic objectForKey:@"Robot"];
        if(arr){
            NSInteger tag = ((NSNumber*)[arr firstObject]).integerValue;
            UIView *viewTarget = [self.view viewWithTag:tag];
            if(viewTarget){
                [self walkToView:viewTarget fromView:self.imgVRobot];
            }
            
        }
        
        arr = [dic objectForKey:@"Box"];
        if(arr){
            UIView *viewBox = [self.mArrScope objectAtIndex:((NSNumber*)[arr lastObject]).integerValue];
            if(viewBox){
                NSInteger tag = ((NSNumber*)[arr firstObject]).integerValue;
                UIView *viewTarget = [self.view viewWithTag:tag];
                if(viewTarget){
                    [self walkToView:viewTarget fromView:viewBox];
                }
            }
        }
        [ViewController playSoundWithName:@"SpecSelectCard" type:@"mp3"];
        
        [mArrTrace removeLastObject];
    }
}

- (void)btnClicked:(UIButton*)btn {
    if(btn.tag == 199000000){
        
    }else if(btn.tag == 199000001){
        [self walkBack];
        
    }else if(btn.tag == 199000002){
        // 重置
        [self setupBox];
    }
}

- (void)dealloc {
    [self cleanSelf];
}

- (void)cleanSelf {
    [mArrTrace removeAllObjects]; mArrTrace = nil;
    
    avAudioPlayer.delegate = nil;
    [avAudioPlayer stop];
    avAudioPlayer = nil;
    
    if(self.mArrData){
        [self.mArrData removeAllObjects];
        self.mArrData = nil;
    }
    
    if(self.mArrFilted){
        [self.mArrFilted removeAllObjects];
        self.mArrFilted = nil;
    }
    
    if(self.mArrScope){
        [self.mArrScope removeAllObjects];
        self.mArrScope = nil;
    }
}

#pragma mark 手势识别处理

- (void)handleViewTapChanged:(UITapGestureRecognizer*)sender {
    [self walkForward:sender.view];
}

// 如果用户再拖动，上一次动画移动完后，检查是否继续移动以及移动方向
- (void)handlePanGesture:(UIPanGestureRecognizer*)sender {
    //    NSLog(@"%ld, %lu", (long)sender.state, (unsigned long)[self commitTranslation:[sender translationInView:self.view]]);
    
    if(sender.state==UIGestureRecognizerStateChanged){
        UISwipeGestureRecognizerDirection direct = [self commitTranslation:[sender translationInView:self.view]];
        if(direct>0)
            [self moveWithDirect:direct];
    }
}

- (void)handleSwipeGesture:(UISwipeGestureRecognizer*)sender {
    [self moveWithDirect:sender.direction];
}

- (void)moveWithDirect:(UISwipeGestureRecognizerDirection)direct {
    // 找到机器人位置
    // 机器人位置
    NSInteger row1 = (self.imgVRobot.tag/timesOfBox)/100;
    NSInteger column1 = (self.imgVRobot.tag/timesOfBox)%100;
    
    // 移动的下一个位置
    NSInteger row2 = 0;
    NSInteger column2 = 0;
    
    switch (direct) {
        case UISwipeGestureRecognizerDirectionLeft: {
            row2 = row1;
            column2 = column1-1;
        } break;
            
        case UISwipeGestureRecognizerDirectionRight: {
            row2 = row1;
            column2 = column1+1;
        } break;
            
        case UISwipeGestureRecognizerDirectionUp: {
            row2 = row1-1;
            column2 = column1;
        } break;
            
        default: {
            row2 = row1+1;
            column2 = column1;
        } break;
    }
    
    UIView *view = [self.view viewWithTag:row2*100+column2];
    if(view){
        // 检查是否存在对应的箱子
        UIView *viewB = [self.view viewWithTag:view.tag*timesOfBox];
        [self walkForward:viewB?viewB:view];
    }
}

- (UISwipeGestureRecognizerDirection)commitTranslation:(CGPoint)translation {
    CGFloat absX = fabs(translation.x);
    CGFloat absY = fabs(translation.y);
    
    
    if (absX > absY ) {
        
        if (translation.x<0) {
            return UISwipeGestureRecognizerDirectionLeft;
            //向左滑动
        }else{
            return UISwipeGestureRecognizerDirectionRight;
            //向右滑动
        }
        
    } else if (absY > absX) {
        if (translation.y<0) {
            return UISwipeGestureRecognizerDirectionUp;
            //向上滑动
        }else{
            return UISwipeGestureRecognizerDirectionDown;
            //向下滑动
        }
    }
    
    return UISwipeGestureRecognizerDirectionLeft;
}


+ (SystemSoundID)playSoundWithName:(NSString *)name type:(NSString *)type {
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:type];
    
    SystemSoundID sound;
    
    if([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &sound);
        AudioServicesPlaySystemSound(sound);
    }
    else {
        NSLog(@"Error: audio file not found at path: %@", path);
    }
    
    return sound;
}

@end
