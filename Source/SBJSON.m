/*
Copyright (C) 2008 Stig Brautaset. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

  Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

  Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

  Neither the name of the author nor the names of its contributors may be used
  to endorse or promote products derived from this software without specific
  prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "SBJSON.h"
#import "SBJSONScanner.h"

NSString * SBJSONErrorDomain = @"org.brautaset.JSON.ErrorDomain";

#define ui(s) [NSDictionary dictionaryWithObject:s forKey:NSLocalizedDescriptionKey]

@interface SBJSON (Private)

- (BOOL)appendValue:(id)fragment into:(NSMutableString*)json error:(NSError**)error;
- (BOOL)appendArray:(NSArray*)fragment into:(NSMutableString*)json error:(NSError**)error;
- (BOOL)appendDictionary:(NSDictionary*)fragment into:(NSMutableString*)json error:(NSError**)error;
- (BOOL)appendString:(NSString*)fragment into:(NSMutableString*)json error:(NSError**)error;

- (NSString*)indent;

@end


@implementation SBJSON

- (id)init {
    if (self = [super init]) {
        [self setMaxDepth:512];
    }
    return self;
}

#pragma mark Generator

- (NSString*)stringWithJSON:(id)value error:(NSError**)error {
    depth = 0;
    NSMutableString *json = [NSMutableString stringWithCapacity:128];
    
    NSError *err;
    if ([self appendValue:value into:json error:&err])
        return json;
    
    if (error)
        *error = err;
    return nil;
}

- (NSString*)indent {
    return [self humanReadable]
    ? [@"\n" stringByPaddingToLength:1 + 2 * depth withString:@" " startingAtIndex:0]
    : @"";
}

- (BOOL)appendValue:(id)fragment into:(NSMutableString*)json error:(NSError**)error {
    if ([fragment isKindOfClass:[NSDictionary class]]) {
        if (![self appendDictionary:fragment into:json error:error])
            return NO;
        
    } else if ([fragment isKindOfClass:[NSArray class]]) {
        if (![self appendArray:fragment into:json error:error])
            return NO;

    } else if ([fragment isKindOfClass:[NSString class]]) {
        if (![self appendString:fragment into:json error:error])
            return NO;

    } else if ([fragment isKindOfClass:[NSNumber class]]) {
        if ('c' == *[fragment objCType])
            [json appendString:[fragment boolValue] ? @"true" : @"false"];
        else
            [json appendString:[fragment stringValue]];

    } else if ([fragment isKindOfClass:[NSNull class]]) {
        [json appendString:@"null"];
        
    } else {
        NSString *message = [NSString stringWithFormat:@"JSON serialisation not supported for %@", [fragment className]];
        NSDictionary *ui = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
        *error = [NSError errorWithDomain:SBJSONErrorDomain code:EUNSUPPORTED userInfo:ui];
        return NO;
    }
    return YES;
}

- (BOOL)appendArray:(NSArray*)fragment into:(NSMutableString*)json error:(NSError**)error {
    [json appendString:@"["];
    depth++;
    
    BOOL addComma = NO;    
    NSEnumerator *values = [fragment objectEnumerator];
    for (id value; value = [values nextObject]; addComma = YES) {
        if (addComma)
            [json appendString:@","];
        
        if ([self humanReadable])
            [json appendString:[self indent]];
        
        if (![self appendValue:value into:json error:error]) {
            return NO;
        }
    }

    depth--;
    if ([self humanReadable] && [fragment count])
        [json appendString:[self indent]];
    [json appendString:@"]"];
    return YES;
}

- (BOOL)appendDictionary:(NSDictionary*)fragment into:(NSMutableString*)json error:(NSError**)error {
    [json appendString:@"{"];
    depth++;

    NSString *colon = [self humanReadable] ? @" : " : @":";
    BOOL addComma = NO;
    NSEnumerator *values = [fragment keyEnumerator];
    for (id value; value = [values nextObject]; addComma = YES) {
        
        if (addComma)
            [json appendString:@","];

        if ([self humanReadable])
            [json appendString:[self indent]];
        
        if (![value isKindOfClass:[NSString class]]) {
            NSDictionary *ui = [NSDictionary dictionaryWithObject:@"JSON object key must be string" forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:SBJSONErrorDomain code:EUNSUPPORTED userInfo:ui];
            return NO;
        }
        
        if (![self appendString:value into:json error:error])
            return NO;

        [json appendString:colon];
        if (![self appendValue:[fragment objectForKey:value] into:json error:error]) {
            NSString *message = [NSString stringWithFormat:@"Unsupported value for key %@ in object", value];
            NSDictionary *ui = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:SBJSONErrorDomain code:EUNSUPPORTED userInfo:ui];
            return NO;
	}
    }

    depth--;
    if ([self humanReadable] && [fragment count])
        [json appendString:[self indent]];
    [json appendString:@"}"];
    return YES;    
}

- (BOOL)appendString:(NSString*)fragment into:(NSMutableString*)json error:(NSError**)error {

    static NSMutableCharacterSet *kEscapeChars;
    if( ! kEscapeChars ) {
        kEscapeChars = [[NSMutableCharacterSet characterSetWithRange: NSMakeRange(0,32)] retain];
        [kEscapeChars addCharactersInString: @"\"\\"];
    }
    
    [json appendString:@"\""];
    
    NSRange esc = [fragment rangeOfCharacterFromSet:kEscapeChars];
    if ( !esc.length ) {
        // No special chars -- can just add the raw string:
        [json appendString:fragment];
        
    } else {
        for (unsigned i = 0; i < [fragment length]; i++) {
            unichar uc = [fragment characterAtIndex:i];
            switch (uc) {
                case '"':   [json appendString:@"\\\""];       break;
                case '\\':  [json appendString:@"\\\\"];       break;
                case '\t':  [json appendString:@"\\t"];        break;
                case '\n':  [json appendString:@"\\n"];        break;
                case '\r':  [json appendString:@"\\r"];        break;
                case '\b':  [json appendString:@"\\b"];        break;
                case '\f':  [json appendString:@"\\f"];        break;
                default:    
                    if (uc < 0x20) {
                        [json appendFormat:@"\\u%04x", uc];
                    } else {
                        [json appendFormat:@"%C", uc];
                    }
                    break;
                    
            }
        }
    }

    [json appendString:@"\""];
    return YES;
}

#pragma mark Scanner

- (id)fragmentWithString:(NSString*)repr error:(NSError**)error {
    id o;
    SBJSONScanner *scanner = [[SBJSONScanner alloc] initWithString:repr];
    [scanner setMaxDepth:[self maxDepth]];

    NSError *err = nil;
    BOOL success = [scanner scanValue:&o error:&err];
    
    if (success && ![scanner isAtEnd]) {
        err = [NSError errorWithDomain:SBJSONErrorDomain code:ETRAILGARBAGE userInfo:ui(@"Garbage after JSON fragment")];
        success = NO;
    }
    
    [scanner release];
    
    if (success)
        return o;
    if (error)
        *error = err;
    return nil;
}

- (id)objectWithString:(NSString*)repr error:(NSError**)error {
    
    NSError *err = nil;
    id o = [self fragmentWithString:repr error:&err];

    if (o && ([o isKindOfClass:[NSDictionary class]] || [o isKindOfClass:[NSArray class]]))
        return o;
    
    if (o) {
        NSDictionary *ui = [NSDictionary dictionaryWithObject:@"Valid fragment, but not JSON" forKey: NSLocalizedDescriptionKey];
        err = [NSError errorWithDomain:SBJSONErrorDomain code:EFRAGMENT userInfo:ui];
    }
    
    if (error)
        *error = err;

    return nil;
}

#pragma mark Properties

- (BOOL)humanReadable {
    return humanReadable;
}

- (void)setHumanReadable:(BOOL)y {
    humanReadable = y;
}

- (unsigned)maxDepth {
    return maxDepth;
}

- (void)setMaxDepth:(unsigned)y {
    maxDepth = y;
}

@end
