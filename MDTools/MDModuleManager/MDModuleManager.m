//
//  MDModuleManager.m
//  MDTools.h
//
//  Created by Larkin Yang on 2017/7/12.
//  Copyright © 2017年 BTCC. All rights reserved.
//

#import "MDModuleManager.h"
#import "MDProtocolImplementation.h"
#import <objc/runtime.h>
#import "UIViewController+ModuleManager.h"
#import "NSObject+Aspects.h"


@interface _MVVMViewModuleWeakContainer : NSObject

@property (nonatomic, weak) id object;

@end

@implementation _MVVMViewModuleWeakContainer

+ (_MVVMViewModuleWeakContainer *)containerWithObject:(id)object {
    _MVVMViewModuleWeakContainer *res = [[_MVVMViewModuleWeakContainer alloc] init];
    res.object = object;
    return res;
}

@end

@implementationProtocol(MDModuleManager)

#pragma mark - private method

- (_MVVMViewModuleWeakContainer *)_lastViewControllerContainer {
    _MVVMViewModuleWeakContainer *container = objc_getAssociatedObject(self, "__lastViewControllerContainer");
    if (!container) {
        container = [[_MVVMViewModuleWeakContainer alloc] init];
        objc_setAssociatedObject(self, "__lastViewControllerContainer", container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return container;
}

- (void)_removeLastViewControllerContainer {
    objc_setAssociatedObject(self, "__lastViewControllerContainer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSMutableArray *)_mutableViewController {
    NSMutableArray *mutableViewControllerss = objc_getAssociatedObject(self, "__viewControllers");
    if (!mutableViewControllerss) {
        mutableViewControllerss = [NSMutableArray array];
        objc_setAssociatedObject(self, "__viewControllers", mutableViewControllerss, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return mutableViewControllerss;
}

- (BOOL)_containViewController:(UIViewController *)viewController {
    for (_MVVMViewModuleWeakContainer *v in self._mutableViewController) {
        if (v.object == viewController) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)_isSuperModuleManagerOfViewController:(UIViewController *)viewController {
    id <MDModuleManager> mm = viewController.moduleManager;
    while (mm) {
        if (mm == self) {
            return YES;
        }
        mm = mm.superModuleManager;
    }
    return NO;
}

- (void)_removeViewControllers:(NSArray *)viewControllers {
    NSMutableArray *array = [NSMutableArray array];
    [self._mutableViewController enumerateObjectsUsingBlock:^(_MVVMViewModuleWeakContainer *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([viewControllers containsObject:[obj object]]) {
            [array addObject:obj];
        }
    }];
    [self._mutableViewController removeObjectsInArray:array];
}

- (NSMutableArray *)_aspectTokens {
    NSMutableArray *_aspectTokens = objc_getAssociatedObject(self, "__aspectTokens");
    if (!_aspectTokens) {
        _aspectTokens = [NSMutableArray array];
        objc_setAssociatedObject(self, "__aspectTokens", _aspectTokens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return _aspectTokens;
}

- (void)_addAspectWithSelector:(SEL)sel block:(void (^)(id<NSObjectAspectInfo> info))block {
    NSError *error;
    id token = [self.navigationController aspect_insertBeforeSelector:sel block:block];
    if (token) {
        [[self _aspectTokens] addObject:token];
    } else {
        NSLog(@"<Aspect: %@>", error);
    }
}

- (void)_loadAspects {
    __weak typeof(self) weakSelf = self;
    
    [self _addAspectWithSelector:@selector(popViewControllerAnimated:)
                           block:^(id<NSObjectAspectInfo> info) {
                               typeof(weakSelf) self = weakSelf;
                               UIViewController *lastViewController = self.navigationController.viewControllers.lastObject;
                               dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                   if (self.tailViewController == lastViewController) {
                                       self._lastViewControllerContainer.object = self.tailViewController;
                                       
                                       [lastViewController aspect_insertBeforeSelector:NSSelectorFromString(@"dealloc") block:^(id<NSObjectAspectInfo> info) {
                                           typeof(weakSelf) self = weakSelf;
                                           if (!self._lastViewControllerContainer.object) {
                                               self.tailViewController.moduleManager = nil;
                                               [self._mutableViewController removeLastObject];
                                               [self _removeLastViewControllerContainer];
                                           }
                                       }];
                                   }
                               });
                           }];
    
    [self _addAspectWithSelector:@selector(popToViewController:animated:) block:^(id<NSObjectAspectInfo> info) {
        typeof(weakSelf) self = weakSelf;
        NSUInteger index = [self.navigationController.viewControllers indexOfObject:info.arguments[0]] + 1;
        NSArray *res = [self.navigationController.viewControllers subarrayWithRange:NSMakeRange(index, self.navigationController.viewControllers.count - index)];
        [res enumerateObjectsUsingBlock:^(UIViewController *viewController, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([weakSelf _containViewController:viewController]) {
                viewController.moduleManager = nil;
            }
        }];
        [self _removeViewControllers:res];
    }];
    
    [self _addAspectWithSelector:@selector(popToRootViewControllerAnimated:)
                           block:^(id<NSObjectAspectInfo> info) {
                               typeof(weakSelf) self = weakSelf;
                               if (self.rootViewController == self.navigationController.viewControllers.firstObject) {
                                   [self._mutableViewController enumerateObjectsUsingBlock:^(_MVVMViewModuleWeakContainer *viewControllerValue, NSUInteger idx, BOOL * _Nonnull stop) {
                                       if (idx) {
                                           [[viewControllerValue object] setModuleManager:nil];
                                       }
                                   }];
                                   
                                   [self._mutableViewController removeAllObjects];
                                   [self._mutableViewController addObject:[_MVVMViewModuleWeakContainer containerWithObject:self.navigationController.viewControllers.firstObject]];
                               } else {
                                   for (_MVVMViewModuleWeakContainer *viewControllerValue in self._mutableViewController) {
                                       [[viewControllerValue object] setModuleManager:nil];
                                   }
                                   [self._mutableViewController removeAllObjects];
                               }
                           }];
    
    [self _addAspectWithSelector:@selector(setViewControllers:)
                           block:^(id<NSObjectAspectInfo> info) {
                               typeof(weakSelf) self = weakSelf;
                               [[self _mutableViewController] removeAllObjects];
                               for (UIViewController *vc in [info arguments][0]) {
                                   if ([self _isSuperModuleManagerOfViewController:vc]) {
                                       [[self _mutableViewController] addObject:[_MVVMViewModuleWeakContainer containerWithObject:vc]];
                                   }
                               }
                           }];
    
    [self _addAspectWithSelector:@selector(setViewControllers:animated:)
                           block:^(id<NSObjectAspectInfo> info) {
                               typeof(weakSelf) self = weakSelf;
                               [[self _mutableViewController] removeAllObjects];
                               for (UIViewController *vc in [info arguments][0]) {
                                   if ([self _isSuperModuleManagerOfViewController:vc]) {
                                       [[self _mutableViewController] addObject:[_MVVMViewModuleWeakContainer containerWithObject:vc]];
                                   }
                               }
                           }];
}

- (void)_unloadAspects {
    for (id token in self._aspectTokens) {
        [self.navigationController aspect_removeBlock:token];
    }
    [self._aspectTokens removeAllObjects];
}

- (void)dealloc {
    [self _unloadAspects];
}

#pragma mark - property

- (instancetype)initWithNavigationController:(UINavigationController *)navigationController{
    if (self = [self init]) {
        self.navigationController = navigationController;
    }
    return self;
}

- (UIViewController *)rootViewController {
    if (self._mutableViewController.count == 0) {
        
        UIViewController *viewController = [self generateRootViewController];
        viewController.moduleManager = self;
        [self._mutableViewController addObject:[_MVVMViewModuleWeakContainer containerWithObject:viewController]];
        
        return viewController;
    }
    return [self._mutableViewController.firstObject object];
}

- (UIViewController *)tailViewController {
    if (self._mutableViewController.count == 0) {
        
        UIViewController *viewController = [self generateRootViewController];
        viewController.moduleManager = self;
        [self._mutableViewController addObject:[_MVVMViewModuleWeakContainer containerWithObject:viewController]];
        
        return viewController;
    }
    return [self._mutableViewController.lastObject object];
}

- (NSArray<UIViewController *> *)viewControllers {
    NSMutableArray <UIViewController *> *result = [NSMutableArray arrayWithCapacity:self._mutableViewController.count];
    for (_MVVMViewModuleWeakContainer *c in self._mutableViewController) {
        [result addObject:c.object];
    }
    return result;
}

- (UINavigationController *)navigationController {
    id (^block)(void) = objc_getAssociatedObject(self, "__navigationController");
    return block ? block() : nil;
}

- (void)setNavigationController:(UINavigationController *)navigationController {
    id (^block)(void) = objc_getAssociatedObject(self, "__navigationController");
    UINavigationController *_navigationController = block ? block() : nil;
    if (!_navigationController) {
        
        __weak id weakObject = navigationController;
        id (^theBlock)(void) = ^{
            return weakObject;
        };
        objc_setAssociatedObject(self, "__navigationController", theBlock, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self _unloadAspects];
        [self _loadAspects];
    } else if (_navigationController != navigationController && navigationController) {
        NSCAssert(NO, @"navigationController can only be called once.");
    }
}

#pragma mark - public method

- (UIViewController *)generateRootViewController {
    return [[UIViewController alloc] init];
}

- (NSArray<UIViewController *> *)popAllViewControllersAnimated:(BOOL)animated {
    if (!self.navigationController) {
        return nil;
    }
    if (self._mutableViewController.count >= self.navigationController.viewControllers.count) {
        return nil;
    }
    if (self.navigationController.viewControllers.lastObject != self.tailViewController) {
        return nil;
    }
    for (_MVVMViewModuleWeakContainer *viewControllerValue in self._mutableViewController) {
        [[viewControllerValue object] setModuleManager:nil];
    }
    NSArray *res = self._mutableViewController.copy;
    NSUInteger index = [self.navigationController.viewControllers indexOfObject:self.rootViewController] - 1;
    UIViewController *toViewController = self.navigationController.viewControllers[index];
    if (self.superModuleManager) {
        return [self.superModuleManager popToViewController:toViewController animated:animated];
    }
    [self.navigationController popToViewController:toViewController animated:animated];
    
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:res.count];
    [res enumerateObjectsUsingBlock:^(_MVVMViewModuleWeakContainer *obj, NSUInteger idx, BOOL *stop) {
        UIViewController *value = obj.object;
        [result addObject:value];
    }];
    return result;
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (!viewController) {
        return;
    }
    if (!self.navigationController) {
        return;
    }
    if (self._mutableViewController.count > self.navigationController.viewControllers.count) {
        return;
    }
    if (self.tailViewController != self.navigationController.viewControllers.lastObject) {
        return;
    }
    [self._mutableViewController addObject:[_MVVMViewModuleWeakContainer containerWithObject:viewController]];
    if (self.superModuleManager) {
        [self.superModuleManager pushViewController:viewController animated:animated];
        viewController.moduleManager = self;
        return;
    }
    [self.navigationController pushViewController:viewController animated:animated];
    viewController.moduleManager = self;
}

- (void)popViewControllerAnimated:(BOOL)animated {
    if (!self.navigationController) {
        return;
    }
    if (self._mutableViewController.count > self.navigationController.viewControllers.count) {
        return;
    }
    if (self.tailViewController != self.navigationController.viewControllers.lastObject) {
        return;
    }
    if (self.rootViewController == self.tailViewController) {
        return;
    }
    if (self.superModuleManager) {
        [self.superModuleManager popViewControllerAnimated:animated];
        return;
    }
    [self.navigationController popViewControllerAnimated:animated];
}

- (NSArray<UIViewController *> *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (!self.navigationController) {
        return nil;
    }
    if (![self _containViewController:viewController]) {
        return nil;
    }
    if (self._mutableViewController.count > self.navigationController.viewControllers.count) {
        return nil;
    }
    if (self.tailViewController != self.navigationController.viewControllers.lastObject) {
        return nil;
    }
    if (self.superModuleManager) {
        return [self.superModuleManager popToViewController:viewController animated:animated];
    }
    return [self.navigationController popToViewController:viewController animated:animated];
}

- (NSArray<UIViewController *> *)popToRootViewControllerAnimated:(BOOL)animated {
    return [self popToViewController:self.rootViewController animated:animated];
}

- (void)preprocessWithFinish:(void (NS_NOESCAPE ^)(id error))finish {
    finish(nil);
}

- (BOOL)removeViewController:(UIViewController *)viewController {
    if (viewController.moduleManager != self) {
        return NO;
    }
    if (![self.navigationController.viewControllers containsObject:viewController]) {
        return YES;
    }
    for (_MVVMViewModuleWeakContainer *c in [self _mutableViewController]) {
        if (c.object == viewController) {
            NSMutableArray *vcs = self.navigationController.viewControllers.mutableCopy;
            [vcs removeObject:viewController];
            self.navigationController.viewControllers = vcs;
            return YES;
        }
    }
    return NO;
}

- (void)removeViewControllers:(NSArray<UIViewController *> *)viewControllers {
    NSMutableArray *vcs = self.navigationController.viewControllers.mutableCopy;
    for (UIViewController *viewController in viewControllers) {
        if (viewController.moduleManager != self) {
            continue;
        }
        if (![self.navigationController.viewControllers containsObject:viewController]) {
            continue;
        }
        for (_MVVMViewModuleWeakContainer *c in [self _mutableViewController]) {
            if (c.object == viewController) {
                [vcs removeObject:viewController];
            }
        }
    }
    self.navigationController.viewControllers = vcs;
}

#pragma mark - submodule

- (id<MDModuleManager>)superModuleManager {
    return objc_getAssociatedObject(self, "__superModuleManager");
}

- (void)setSuperModuleManager:(id<MDModuleManager>)superModuleManager {
    if (self.superModuleManager != superModuleManager) {
        objc_setAssociatedObject(self, "__superModuleManager", superModuleManager, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)pushSubModuleManager:(id <MDModuleManager>)moduleManager animated:(BOOL)animated {
    moduleManager.superModuleManager = self;
    moduleManager.navigationController = self.navigationController;
    UIViewController *vc = moduleManager.rootViewController;
    [self pushViewController:vc animated:animated];
    vc.moduleManager = moduleManager;
}

@end
