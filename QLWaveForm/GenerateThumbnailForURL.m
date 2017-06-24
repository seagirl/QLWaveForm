#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#include <Cocoa/Cocoa.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/ExtendedAudioFile.h>

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize);
void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail);
void CheckStatus(OSStatus status, NSString *message);

/* -----------------------------------------------------------------------------
    Generate a thumbnail for file

   This function's job is to create thumbnail for designated file as fast as possible
   ----------------------------------------------------------------------------- */

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize)
{
    // To complete your generator please implement the function GenerateThumbnailForURL in GenerateThumbnailForURL.c
	
	OSStatus status;
	ExtAudioFileRef file;
	
	status = ExtAudioFileOpenURL(url, &file);
	CheckStatus(status, @"ExtAudioFileOpenURL");

	AudioStreamBasicDescription format;
	format.mChannelsPerFrame = 2;
	format.mSampleRate = 48000;
	format.mBitsPerChannel = 8 * sizeof(AudioSampleType); // 32bit
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
	format.mFramesPerPacket = 1;
	format.mBytesPerPacket = sizeof(AudioSampleType) * format.mChannelsPerFrame;
	format.mBytesPerFrame = sizeof(AudioSampleType) * format.mChannelsPerFrame;
	format.mReserved = 0;
	
	status = ExtAudioFileSetProperty(file,
									 kExtAudioFileProperty_ClientDataFormat,
									 sizeof(format),
									 &format);
	CheckStatus(status, @"ExtAudioFileSetProperty");
	
	status = ExtAudioFileSeek(file, 0);
	CheckStatus(status, @"ExtAudioFileSeek");
	
	UInt32 readFrameSize = 1024;
	UInt32 bufferSize = format.mBytesPerFrame * readFrameSize;
	AudioUnitSampleType *buffer = malloc(bufferSize);
	
	AudioBufferList audioBufferList;
	audioBufferList.mNumberBuffers = 1;
	audioBufferList.mBuffers[0].mNumberChannels = format.mChannelsPerFrame;
	audioBufferList.mBuffers[0].mDataByteSize = bufferSize;
	audioBufferList.mBuffers[0].mData = buffer;
	
	NSMutableArray *array = [NSMutableArray array];
	
	while (1) {		
		status = ExtAudioFileRead(file, &readFrameSize, &audioBufferList);
		CheckStatus(status, @"ExtAudioFileRead");
		
		if (readFrameSize == 0) {
			break;
		}
		
		for (int j = 0; j < readFrameSize; j++) {
			AudioUnitSampleType *value = audioBufferList.mBuffers[0].mData;
			float l = *(value++);
			float r = *(value++);
			if (j == 0) {
				[array addObject:[NSNumber numberWithFloat:(l + r) / 2]];
			}
		}
	}
	
	status = ExtAudioFileDispose(file);
	CheckStatus(status, @"ExtAudioFileDispose");
	
	free(buffer);

    NSDictionary *dict = @{[NSString stringWithFormat:@"%@", kQLPreviewPropertyWidthKey]: [NSNumber numberWithInt:maxSize.width],
						   [NSString stringWithFormat:@"%@", kQLPreviewPropertyHeightKey]: [NSNumber numberWithInt:maxSize.height]};
	
    CGContextRef cgContext = QLThumbnailRequestCreateContext(thumbnail, maxSize, false, (__bridge CFDictionaryRef)dict);
	
    if (cgContext) {
        NSGraphicsContext* context = [NSGraphicsContext
									  graphicsContextWithGraphicsPort:(void *)cgContext
									  flipped:YES];
        if (context) {
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:context];
			
			[[NSColor blackColor] set];
			
			NSPoint lastPoint;
			for (int i = 0; i < [array count]; i++) {
				float v = [[array objectAtIndex:i] floatValue];
				
				NSPoint point = NSMakePoint(maxSize.width * i / [array count], maxSize.height * v * 0.5 + maxSize.height / 2);
				
				if (i > 0) {
					[NSBezierPath strokeLineFromPoint:lastPoint toPoint:point];
				}
				
				lastPoint = point;
			}
			
            [NSGraphicsContext restoreGraphicsState];
        }
		
        QLThumbnailRequestFlushContext(thumbnail, cgContext);
        CFRelease(cgContext);
    }
	
    return noErr;
}

void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail)
{
    // Implement only if supported
}

void CheckStatus(OSStatus status, NSString *message)
{
	if(status != noErr)
	{
		char fourCC[16];
		*(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
		fourCC[4] = '\0';
		
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
			NSLog(@"%@: %s", message, fourCC);
		else
			NSLog(@"%@: %d", message, status);
	}
}