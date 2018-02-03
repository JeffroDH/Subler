//
//  MetadataResult.swift
//  Subler
//
//  Created by Damiano Galassi on 08/08/2017.
//

import Foundation

// MARK: - Image

@objc(SBArtworkType) public enum ArtworkType : Int, CustomStringConvertible {
    public var description: String {
        switch self {
        case .poster:
            return "poster"
        case .season:
            return "season"
        case .square:
            return "square"
        case .episode:
            return "episode"
        case .backdrop:
            return "backdrop"
        case .iTunes:
            return "iTunes"
        }
    }

    case poster
    case season
    case square
    case episode
    case backdrop
    case iTunes
}

public struct Artwork {
    public let url: URL
    public let thumbURL: URL
    public let service: String
    public let type: ArtworkType
}

private let localizedKeys: [MetadataResult.Key: String] = [
    .name             : NSLocalizedString("Name", comment: "nil"),
    .composer         : NSLocalizedString("Composer", comment: "nil"),
    .genre            : NSLocalizedString("Genre", comment: "nil"),
    .releaseDate      : NSLocalizedString("Release Date", comment: "nil"),
    .description      : NSLocalizedString("Description", comment: "nil"),
    .longDescription  : NSLocalizedString("Long Description", comment: "nil"),
    .rating           : NSLocalizedString("Rating", comment: "nil"),
    .studio           : NSLocalizedString("Studio", comment: "nil"),
    .cast             : NSLocalizedString("Cast", comment: "nil"),
    .director         : NSLocalizedString("Director", comment: "nil"),
    .producers        : NSLocalizedString("Producers", comment: "nil"),
    .screenwriters    : NSLocalizedString("Screenwriters", comment: "nil"),
    .executiveProducer: NSLocalizedString("Executive Producer", comment: "nil"),
    .copyright        : NSLocalizedString("Copyright", comment: "nil"),

    .contentID        : NSLocalizedString("contentID", comment: "nil"),
    .artistID         : NSLocalizedString("artistID", comment: "nil"),
    .playlistID       : NSLocalizedString("playlistID", comment: "nil"),
    .iTunesCountry    : NSLocalizedString("iTunes Country", comment: "nil"),
    .iTunesURL        : NSLocalizedString("iTunes URL", comment: "nil"),

    .seriesName       : NSLocalizedString("Series Name", comment: "nil"),
    .seriesDescription: NSLocalizedString("Series Description", comment: "nil"),
    .trackNumber      : NSLocalizedString("Track #", comment: "nil"),
    .diskNumber       : NSLocalizedString("Disk #", comment: "nil"),
    .episodeNumber    : NSLocalizedString("Episode #", comment: "nil"),
    .episodeID        : NSLocalizedString("Episode ID", comment: "nil"),
    .season           : NSLocalizedString("Season", comment: "nil"),
    .network          : NSLocalizedString("Network", comment: "nil"),

    .serviceSeriesID  : NSLocalizedString("Service ID", comment: "nil"),
    .serviceEpisodeID : NSLocalizedString("Service ID", comment: "nil")
]

public class MetadataResult : NSObject {

    public enum Key: String {
        // Common Keys
        case name               = "{Name}"
        case composer           = "{Composer}"
        case genre              = "{Genre}"
        case releaseDate        = "{Release Date}"
        case description        = "{Description}"
        case longDescription    = "{Long Description}"
        case rating             = "{Rating}"
        case studio             = "{Studio}"
        case cast               = "{Cast}"
        case director           = "{Director}"
        case producers          = "{Producers}"
        case screenwriters      = "{Screenwriters}"
        case executiveProducer  = "{Executive Producer}"
        case copyright          = "{Copyright}"

        case mediaKind          = "{MediaKind}"
        case contentRating      = "{ContentRating}"

        // iTunes Keys
        case contentID          = "{contentID}"
        case artistID           = "{artistID}"
        case playlistID         = "{playlistID}"
        case iTunesCountry      = "{iTunes Country}"
        case iTunesURL          = "{iTunes URL}"

        // TV Show Keys
        case seriesName         = "{Series Name}"
        case seriesDescription  = "{Series Description}"
        case trackNumber        = "{Track #}"
        case diskNumber         = "{Disk #}"
        case episodeNumber      = "{Episode #}"
        case episodeID          = "{Episode ID}"
        case season             = "{Season}"
        case network            = "{Network}"

        //
        case serviceSeriesID              = "ServiceSeriesID"
        case serviceAdditionalSeriesID    = "AdditionalServiceSeriesID"
        case serviceEpisodeID             = "ServiceEpisodeID"

        fileprivate static var movieKeys: [Key] {
            return [.name,
                    .composer,
                    .genre,
                    .releaseDate,
                    .description,
                    .longDescription,
                    .rating,
                    .studio,
                    .cast,
                    .director,
                    .producers,
                    .screenwriters,
                    .executiveProducer,
                    .copyright,
                    .contentID,
                    .artistID]
        }

        fileprivate static var tvShowKeys: [Key] {
            return [.name,
                    .seriesName,
                    .composer,
                    .genre,
                    .releaseDate,

                    .trackNumber,
                    .diskNumber,
                    .episodeNumber,
                    .network,
                    .episodeID,
                    .season,

                    .description,
                    .longDescription,
                    .seriesDescription,

                    .rating,
                    .studio,
                    .cast,
                    .director,
                    .producers,
                    .screenwriters,
                    .executiveProducer,
                    .copyright,
                    .contentID,
                    .artistID,
                    .playlistID,
                    .iTunesCountry]
        }

       public var localizedDisplayName: String {
            return localizedKeys[self] ?? "Null"
        }

        public static var movieKeysStrings: [String] {
            return Key.movieKeys.map { $0.rawValue }
        }

        public static var tvShowKeysStrings: [String] {
            return Key.tvShowKeys.map { $0.rawValue }
        }

        public static func localizedDisplayName(key: String) -> String {
            return Key(rawValue: key)?.localizedDisplayName ?? key
        }

    }

    private var dictionary: [Key:Any]

    public var mediaKind: Int
    public var contentRating: Int
    public var remoteArtworks: [Artwork]
    public var artworks: [MP42Image]

    override init() {
        self.dictionary = Dictionary()
        self.remoteArtworks = Array()
        self.artworks = Array()
        self.mediaKind = 0
        self.contentRating = 0
    }

    subscript(key: Key) -> Any? {
        get {
            return dictionary[key]
        }
        set (newValue) {
            dictionary[key] = newValue
        }
    }

    lazy var orderedKeys: [Key] = {
        let sortedKeys = self.mediaKind == 9 ? Key.movieKeys : Key.tvShowKeys
        return Array(dictionary.keys).sorted(by: { (key1: Key, key2: Key) -> Bool in
            if let index1 = sortedKeys.index(of: key1), let index2 = sortedKeys.index(of: key2) {
                return index1 < index2
            }
            return key1 != Key.serviceSeriesID && key1 != Key.serviceEpisodeID
        })
    }()

    public var count: Int {
        return dictionary.count
    }

    public func merge(result: MetadataResult) {
        dictionary.merge(result.dictionary) { (_, new) in new }
    }

    private func isToken(_ string: String) -> Bool {
        return string.hasPrefix("{}") && string.hasSuffix("}") && string.count > 2
    }

    public func mappedMetadata(to map: MetadataResultMap, keepEmptyKeys: Bool) -> MP42Metadata {
        let metadata = MP42Metadata()

        metadata.addItems(map.items.compactMap {
            let value = $0.value.reduce("", {
                if let key = Key(rawValue: $1) {
                    if let value = dictionary[key] {
                        return $0 + "\(value)"
                    }
                    return $0
                }
                else {
                    return $0 + $1
                }
            })
            return value.isEmpty == false || keepEmptyKeys ? MP42MetadataItem(identifier: $0.key,
                                                                              value: value as NSCopying & NSObjectProtocol,
                                                                              dataType: .unspecified, extendedLanguageTag: nil): nil
        })

        metadata.addItems(artworks.map {
            MP42MetadataItem(identifier: MP42MetadataKeyCoverArt,value: $0,
                             dataType: .image, extendedLanguageTag: nil)
        })

        let mediaKind = MP42MetadataItem(identifier: MP42MetadataKeyMediaKind,
                                         value: NSNumber(value: self.mediaKind),
                                         dataType: .integer,
                                         extendedLanguageTag: nil)
        metadata.addItem(mediaKind)

        if contentRating > 0 || keepEmptyKeys {
            let contentRating = MP42MetadataItem(identifier: MP42MetadataKeyContentRating,
                                             value: NSNumber(value: self.contentRating),
                                             dataType: .integer,
                                             extendedLanguageTag: nil)
            metadata.addItem(contentRating)
        }

        return metadata
    }

}
