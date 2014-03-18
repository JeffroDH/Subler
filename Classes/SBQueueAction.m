//
//  SBQueueAction.m
//  Subler
//
//  Created by Damiano Galassi on 12/03/14.
//
//

#import "SBQueueAction.h"

#import "SBQueueItem.h"
#import "MetadataImporter.h"

#import <MP42Foundation/MP42File.h>
#import <MP42Foundation/MP42FileImporter.h>
#import <MP42Foundation/MP42Image.h>
#import <MP42Foundation/MP42Utilities.h>

@implementation SBQueueSubtitlesAction

- (NSArray *)loadSubtitles:(NSURL *)url {
    NSError *outError;
    NSMutableArray *tracksArray = [[NSMutableArray alloc] init];
    NSArray *directory = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[url URLByDeletingLastPathComponent]
                                                       includingPropertiesForKeys:nil
                                                                          options:NSDirectoryEnumerationSkipsSubdirectoryDescendants |
                                                                                  NSDirectoryEnumerationSkipsHiddenFiles |
                                                                                  NSDirectoryEnumerationSkipsPackageDescendants
                                                                            error:nil];

    for (NSURL *dirUrl in directory) {
        if ([[dirUrl pathExtension] isEqualToString:@"srt"]) {
            NSComparisonResult result;
            NSString *movieFilename = [[url URLByDeletingPathExtension] lastPathComponent];
            NSString *subtitleFilename = [[dirUrl URLByDeletingPathExtension] lastPathComponent];
            NSRange range = { 0, [movieFilename length] };

            if ([movieFilename length] <= [subtitleFilename length]) {
                result = [subtitleFilename compare:movieFilename options:NSCaseInsensitiveSearch range:range];

                if (result == NSOrderedSame) {
                    MP42FileImporter *fileImporter = [[[MP42FileImporter alloc] initWithURL:dirUrl
                                                                                      error:&outError] autorelease];

                    for (MP42Track *track in fileImporter.tracks) {
                        [tracksArray addObject:track];
                    }
                }
            }
        }
    }

    return [tracksArray autorelease];
}

- (void)runAction:(SBQueueItem *)item {
    // Search for external subtitles files
    NSArray *subtitles = [self loadSubtitles:item.URL];
    for (MP42SubtitleTrack *subTrack in subtitles) {
        [item.mp4File addTrack:subTrack];
    }
}

@end

@implementation SBQueueMetadataAction

- (MP42Image *)loadArtwork:(NSURL *)url {
    NSData *artworkData = [MetadataImporter downloadDataFromURL:url withCachePolicy:SBDefaultPolicy];
    if (artworkData && [artworkData length]) {
        MP42Image *artwork = [[MP42Image alloc] initWithData:artworkData type:MP42_ART_JPEG];
        if (artwork != nil) {
            return [artwork autorelease];
        }
    }

    return nil;
}

- (MP42Metadata *)searchMetadataForFile:(NSURL *)url {
    id currentSearcher = nil;
    MP42Metadata *metadata = nil;

    // Parse FileName and search for metadata
    NSDictionary *parsed = [MetadataImporter parseFilename:[url lastPathComponent]];
    NSString *type = (NSString *)[parsed valueForKey:@"type"];
    if ([@"movie" isEqualToString:type]) {
		currentSearcher = [MetadataImporter defaultMovieProvider];
		NSString *language = [MetadataImporter defaultMovieLanguage];
		NSArray *results = [currentSearcher searchMovie:[parsed valueForKey:@"title"] language:language];
        if ([results count])
			metadata = [currentSearcher loadMovieMetadata:[results objectAtIndex:0] language:language];
    } else if ([@"tv" isEqualToString:type]) {
		currentSearcher = [MetadataImporter defaultTVProvider];
		NSString *language = [MetadataImporter defaultTVLanguage];
		NSArray *results = [currentSearcher searchTVSeries:[parsed valueForKey:@"seriesName"]
                                                  language:language seasonNum:[parsed valueForKey:@"seasonNum"]
                                                episodeNum:[parsed valueForKey:@"episodeNum"]];
        if ([results count])
			metadata = [currentSearcher loadTVMetadata:[results objectAtIndex:0] language:language];
    }

    if (metadata.artworkThumbURLs && [metadata.artworkThumbURLs count]) {
        NSURL *artworkURL = nil;
        if ([type isEqualToString:@"movie"]) {
            artworkURL = [metadata.artworkFullsizeURLs objectAtIndex:0];
        } else if ([type isEqualToString:@"tv"]) {
            if ([metadata.artworkFullsizeURLs count] > 1) {
                int i = 0;
                for (NSString *artworkProviderName in metadata.artworkProviderNames) {
                    NSArray *a = [artworkProviderName componentsSeparatedByString:@"|"];
                    if ([a count] > 1 && ![[a objectAtIndex:1] isEqualToString:@"episode"]) {
                        artworkURL = [metadata.artworkFullsizeURLs objectAtIndex:i];
                        break;
                    }
                    i++;
                }
            } else {
                artworkURL = [metadata.artworkFullsizeURLs objectAtIndex:0];
            }
        }

        MP42Image *artwork = [self loadArtwork:artworkURL];

        if (artwork)
            [metadata.artworks addObject:artwork];
    }

    return metadata;
}

- (void)runAction:(SBQueueItem *)item {
    // Search for metadata
    MP42Metadata *metadata = [self searchMetadataForFile:item.URL];

    for (MP42Track *track in item.mp4File.tracks)
        if ([track isKindOfClass:[MP42VideoTrack class]]) {
            int hdVideo = isHdVideo([((MP42VideoTrack *) track) trackWidth], [((MP42VideoTrack *) track) trackHeight]);

            if (hdVideo)
                [item.mp4File.metadata setTag:@(hdVideo) forKey:@"HD Video"];
        }

    [[item.mp4File metadata] mergeMetadata:metadata];
}

@end

@implementation SBQueueSetAction

- (void)runAction:(SBQueueItem *)item {
}

@end

@implementation SBQueueOrganizeGroupsAction

- (void)runAction:(SBQueueItem *)item {
    [item.mp4File organizeAlternateGroups];
}

@end