//
//  VLCWebBindingsController.m
//  Lunettes
//
//  Created by Pierre d'Herbemont on 10/26/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "VLCWebBindingsController.h"

// Use bind: or emulate our own
//#define USE_BIND

@interface VLCWebBindingsController (DOMEventListener) <DOMEventListener>
@end

@implementation VLCWebBindingsController
- (id)init
{
    self = [super init];
    if (!self)
        return nil;
    _bindings = [[NSMutableArray alloc] initWithCapacity:1000];
    _observers = [[NSMutableArray alloc] initWithCapacity:3];
    return self;
}

- (void)dealloc
{
    NSAssert([_bindings count] == 0, @"Bindings should be empty");
    [_bindings release];
    NSAssert([_observers count] == 0, @"Observers should be empty");
    [_observers release];
    [super dealloc];
}

#pragma mark -
#pragma mark Observers private getters

- (NSSet *)observersDictsForObject:(id)object andKeypath:(NSString *)keyPath
{
    NSMutableSet *set = [NSMutableSet set];
    for (NSDictionary *dict in _observers) {
        if ([[dict objectForKey:@"object"] isEqual:object] &&
            [[dict objectForKey:@"keyPath"] isEqualToString:keyPath])
            [set addObject:dict];
    }
    return set;
}

- (NSDictionary *)observerDictForObserver:(WebScriptObject *)observer withObject:(id)object andKeypath:(NSString *)keyPath
{
    for (NSDictionary *dict in _observers) {
        if ([[dict objectForKey:@"object"] isEqual:object] &&
            [[dict objectForKey:@"observer"] isEqual:observer] &&
            [[dict objectForKey:@"keyPath"] isEqualToString:keyPath] )
            return [[dict retain] autorelease];
    }
    return nil;
}

static NSMutableArray *arrayOfSubKeys(id object, NSString *keyPath)
{
    NSMutableArray *array = [NSMutableArray array];
    NSString *nextKeyPath = keyPath;
    NSRange range = [nextKeyPath rangeOfString:@"."];
    while (range.location != NSNotFound && object) {
        NSString *key = [nextKeyPath substringToIndex:range.location];
        object = [object valueForKey:key];
        if (!object)
            break;
        [array addObject:object];

        // Prepare next loop
        nextKeyPath = [nextKeyPath substringFromIndex:range.location + 1];
        range = [nextKeyPath rangeOfString:@"."];
    }
    return array;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSDictionary *dict = context;
    NSAssert(dict, @"No dict. Super class shouldn't be observing either.");

    id observer = [dict objectForKey:@"observer"];
    if (observer) {
        WebScriptObject *observer = [dict objectForKey:@"observer"];

        NSInteger kind = [[change objectForKey:NSKeyValueChangeKindKey] intValue];
        id new = [change objectForKey:NSKeyValueChangeNewKey];

        // Get all modified indexes.
        NSMutableArray *setAsArray = nil;
        NSIndexSet *set = [change objectForKey:NSKeyValueChangeIndexesKey];
        if (set) {
            NSUInteger bufSize = [set count];
            setAsArray = [NSMutableArray arrayWithCapacity:bufSize];
            NSUInteger buf[bufSize];
            NSRange range = NSMakeRange([set firstIndex], [set lastIndex]);
            [set getIndexes:buf maxCount:bufSize inIndexRange:&range];
            for(NSUInteger i = 0; i < bufSize; i++) {
                NSUInteger index = buf[i];
                [setAsArray addObject:[NSNumber numberWithInt:index]];
            }
        }

        switch (kind) {
            case NSKeyValueChangeSetting:
                // I sometimes get NSNull value during setting but [object valueForKeyPath:keyPath]
                // returns a better results, so use it. This happen with NSArrayController arrangedObjects.
                new = [object valueForKeyPath:keyPath];

                if ([new isKindOfClass:[NSNull class]])
                    break;

                NSAssert([new isKindOfClass:[NSArray class]], @"Only support array");

                NSMutableArray *array = [NSMutableArray arrayWithCapacity:[new count]];
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
                [new enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    WebScriptObject *cocoaObject = [observer callWebScriptMethod:@"createCocoaObject" withArguments:nil];
                    [array addObject:cocoaObject];
                    [cocoaObject setValue:obj forKey:@"backendObject"];
                }];
#else
                /* FIXME: code missing here!" */
#endif
                [observer callWebScriptMethod:@"setCocoaObjects" withArguments:[NSArray arrayWithObject:array]];
                break;
            case NSKeyValueChangeInsertion:
                for (NSUInteger i = 0; i < [new count]; i++) {
                    id object = [new objectAtIndex:i];
                    WebScriptObject *child = [observer callWebScriptMethod:@"createCocoaObject" withArguments:[NSArray arrayWithObject:observer]];
                    NSAssert(child, @"createCocoaObject() should return something");
                    [child setValue:object forKey:@"backendObject"];
                    [observer callWebScriptMethod:@"insertCocoaObject" withArguments:[NSArray arrayWithObjects:child, [setAsArray objectAtIndex:i], nil]];
                }
                break;
            case NSKeyValueChangeRemoval:
                [observer callWebScriptMethod:@"removeCocoaObjectAtIndexes" withArguments:[NSArray arrayWithObject:setAsArray]];
                break;
            case NSKeyValueChangeReplacement:
            default:
                NSAssert(0, @"Should not be reached");
                break;
        }
        return;

    }
    else {
        // We are in the case of a binding.
        NSMutableDictionary *dictMutable = (NSMutableDictionary *)dict;

#ifndef USE_BIND
        id value = [object valueForKeyPath:keyPath];
#endif
        id bindingObject = [dictMutable objectForKey:@"object"];

        if (bindingObject != object) {
            [dictMutable setObject:arrayOfSubKeys(object, keyPath) forKey:@"arrayOfRetainedSubKeysForObject"];
#ifndef USE_BIND
            if ([[dictMutable objectForKey:@"bindingsControllerIsSetting"] boolValue])
                return;
            id target = bindingObject;
            if (!value || [value isKindOfClass:[NSNull class]])
                return;
            NSString *targetKeyPath = [dictMutable objectForKey:@"keyPath"];
            [dictMutable setObject:[NSNumber numberWithBool:YES] forKey:@"bindingsControllerIsSetting"];
            [target setValue:value forKeyPath:targetKeyPath];
            [dictMutable setObject:[NSNumber numberWithBool:NO] forKey:@"bindingsControllerIsSetting"];
#endif
        } else
        {
            [dictMutable setObject:arrayOfSubKeys(object, keyPath) forKey:@"arrayOfRetainedSubKeysForDomObject"];

#ifndef USE_BIND
            if ([[dictMutable objectForKey:@"bindingsControllerIsSetting"] boolValue])
                return;
            if (!value || [value isKindOfClass:[NSNull class]])
            {
                NSDictionary *options = [dictMutable objectForKey:@"options"];
                if (options) {
                    id obj = [options objectForKey:NSNullPlaceholderBindingOption];
                    if (obj)
                        value = obj;
                }
            }
            id target = [dictMutable objectForKey:@"domObject"];
            NSString *targetKeyPath = [dictMutable objectForKey:@"property"];
            [dictMutable setObject:[NSNumber numberWithBool:YES] forKey:@"bindingsControllerIsSetting"];
            [target setValue:value forKeyPath:targetKeyPath];
            [dictMutable setObject:[NSNumber numberWithBool:NO] forKey:@"bindingsControllerIsSetting"];
#endif
        }

        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)_removeObserverWithDict:(NSDictionary *)dict
{
    id object = [dict objectForKey:@"object"];
    NSString *keyPath = [dict objectForKey:@"keyPath"];

    [object removeObserver:self forKeyPath:keyPath];
    [_observers removeObject:dict];
}

#pragma mark -
#pragma mark Public observer functions

- (void)observe:(id)object withKeyPath:(NSString *)keyPath observer:(WebScriptObject *)observer
{
    NSDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                          object, @"object",
                          observer, @"observer",
                          keyPath, @"keyPath", nil];
    [_observers addObject:dict];
    [object addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:dict];
}

- (void)unobserve:(id)object withKeyPath:(NSString *)keyPath observer:(WebScriptObject *)observer
{
    NSDictionary *dict = [self observerDictForObserver:observer withObject:object andKeypath:keyPath];
    NSAssert(dict, @"No registered observer");
    [self _removeObserverWithDict:dict];
}

#pragma mark -
#pragma mark Bindings private getters

- (NSDictionary *)bindingForDOMObject:(DOMObject *)domObject property:(NSString *)property
{
    for (NSDictionary *dict in _bindings) {
        if ([[dict objectForKey:@"domObject"] isEqual:domObject] &&
            [[dict objectForKey:@"property"] isEqualToString:property])
            return [[dict retain] autorelease];
    }
    return nil;
}

- (NSSet *)bindingsForDOMObject:(DOMObject *)domObject
{
    NSMutableSet *set = [NSMutableSet set];
    for (NSDictionary *dict in _bindings) {
        if ([[dict objectForKey:@"domObject"] isEqual:domObject])
            [set addObject:dict];
    }
    return set;
}

- (void)_removeBindingWithDict:(NSDictionary *)dict
{
    DOMObject *domObject = [dict objectForKey:@"domObject"];
    if ([domObject isKindOfClass:[DOMNode class]]) {
        DOMNode *node = (DOMNode *)domObject;
        [node removeEventListener:@"input" listener:self useCapture:NO];
        [node removeEventListener:@"DOMNodeRemoved" listener:self useCapture:NO];
    }

    NSDictionary *options = [dict objectForKey:@"options"];
    if (![options objectForKey:NSPredicateFormatBindingOption]) {
        NSString *property = [dict objectForKey:@"property"];
        [domObject removeObserver:self forKeyPath:property];
        id object = [dict objectForKey:@"object"];
        NSString *keyPath = [dict objectForKey:@"keyPath"];
        [object removeObserver:self forKeyPath:keyPath];

#ifdef USE_BIND
        [domObject unbind:property];
#endif
    }

    NSUInteger count = [_bindings count];
    [_bindings removeObject:dict];
    NSAssert(count - [_bindings count] == 1, @"");
}

- (void)handleEvent:(DOMEvent *)evt
{
    DOMNode *node = [evt target];
    NSSet *set = [self bindingsForDOMObject:node] ;
    if ([set count] == 0) {
        NSAssert([[evt type] isEqualToString:@"DOMNodeRemoved"], @"Only DOMNodeRemoved can be emitted for children");
        // We are receiving this event for a children
        // Just abort.
        return;
    }

    if ([[evt type] isEqualToString:@"input"]) {
        for (NSDictionary *dict in set) {
            id object = [dict objectForKey:@"object"];
            NSString *keyPath = [dict objectForKey:@"keyPath"];
            NSString *property = [dict objectForKey:@"property"];
            NSDictionary *options = [dict objectForKey:@"options"];
            NSString *predicateFormat = [options objectForKey:NSPredicateFormatBindingOption];
            id value = [node valueForKey:property];
            if (predicateFormat) {
                // If we have a predicate bindings, create it here, and pass it
                // instead of using the value directly.
                if (!value || [value isEqualToString:@""])
                    value = [NSPredicate predicateWithValue:YES];
                else {
                    NSPredicate *predicate = [NSPredicate predicateWithFormat:predicateFormat];
                    value = [predicate predicateWithSubstitutionVariables:[NSDictionary dictionaryWithObject:value forKey:@"value"]];
                }
            }
            [object setValue:value forKeyPath:keyPath];
        }
        return;
    }

    // [evt type] == "DOMNodeRemoved"
    for (NSDictionary *dict in set)
        [self _removeBindingWithDict:dict];
}


#pragma mark -
#pragma mark Public bindings functions

- (void)bindDOMObject:(DOMObject *)domObject property:(NSString *)property toObject:(id)object withKeyPath:(NSString *)keyPath options:(NSDictionary *)options
{
    NSAssert(![self bindingForDOMObject:domObject property:property], ([NSString stringWithFormat:@"Binding of %@.%@ already exists", domObject, property]));

    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:domObject, @"domObject", property, @"property", keyPath, @"keyPath", object, @"object", options, @"options", nil];
    [_bindings addObject:dict];

    if ([domObject isKindOfClass:[DOMNode class]]) {
        DOMNode *node = (DOMNode *)domObject;
        [node addEventListener:@"DOMNodeRemoved" listener:self useCapture:NO];
        [node addEventListener:@"input" listener:self useCapture:NO];
    }

    if ([options objectForKey:NSPredicateFormatBindingOption]) {
        // In the case of a NSPredicateFormatBindingOption
        // we don't really know how to do the other way around.
        // So we stop here.
        // We'll handle the rest via "input" event.
        return;
    }

    [dict setObject:arrayOfSubKeys(object, keyPath) forKey:@"arrayOfRetainedSubKeysForObject"];
    [dict setObject:arrayOfSubKeys(domObject, property) forKey:@"arrayOfRetainedSubKeysForDomObject"];


    [object addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial context:dict];
    [domObject addObserver:self forKeyPath:property options:NSKeyValueObservingOptionNew context:dict];

#ifdef USE_BIND
    [domObject bind:property toObject:object withKeyPath:keyPath options:options];
#endif
}

- (void)unbindDOMObject:(DOMObject *)domObject property:(NSString *)property
{
    NSDictionary * dict = [self bindingForDOMObject:domObject property:property];
    NSAssert(dict, ([NSString stringWithFormat:@"No binding for %@.%@", domObject, property]));
    [self _removeBindingWithDict:dict];
}

- (void)clearBindingsAndObservers
{
    while ([_bindings count] > 0)
        [self _removeBindingWithDict:[_bindings objectAtIndex:0]];
    while ([_observers count] > 0)
        [self _removeObserverWithDict:[_observers objectAtIndex:0]];
}

@end
