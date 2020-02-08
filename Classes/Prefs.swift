//
//  Prefs.swift
//  Subler
//
//  Created by Damiano Galassi on 07/02/2020.
//

import Foundation

private let ud = UserDefaults.standard

private protocol Registable {
    func registerDefault(in dictionary: inout [String :Any])
}

@propertyWrapper
struct Stored<T> : Registable {
    let key: String
    let defaultValue: T

    init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get { ud.object(forKey: key) as? T ?? defaultValue }
        set { ud.set(newValue, forKey: key) }
    }

    func registerDefault(in dictionary: inout [String :Any]) {
        dictionary[key] = defaultValue
    }
}

@propertyWrapper
struct StoredCodable<T: Codable> : Registable {
    let key: String
    let defaultValue: T

    init(key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get {
            guard let data = ud.data(forKey: key) else { return defaultValue }
            let value = try? JSONDecoder().decode(T.self, from: data)
            return value ?? defaultValue
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            ud.set(data, forKey: key)
        }
    }

    func registerDefault(in dictionary: inout [String :Any]) {
        if let data = try? JSONEncoder().encode(defaultValue) {
            dictionary[key] = data
        }
    }
}

struct Prefs {

    static func register() {
        var defaults = [String : Any]()
        ([_saveFormat, _organizeAlternateGroups, _defaultSaveFormat,
          _organizeAlternateGroups, _inferMediaCharacteristics, _audioMixdown,
          _audioBitrate, _audioDRC, _audioConvertAC3, _audioKeepAC3, _audioConvertDts,
          _audioDtsOptions, _subtitleConvertBitmap, _ratingsCountry, _chaptersPreviewPosition,
          _chaptersPreviewTrack, _mp464bitOffset, _mp464bitTimes, _mp4SaveAsOptimize, _forceHvc1]
            as? [Registable])?
            .forEach { $0.registerDefault(in: &defaults) }

        ud.register(defaults: defaults)
    }

    @Stored(key: "SBIgnoreDonationAlert", defaultValue: false)
    static var suppressDonationAlert: Bool

    @Stored(key: "SBShowQueueWindow", defaultValue: false)
    static var showQueueWindow: Bool

    @Stored(key: "rememberWindowSize", defaultValue: false)
    static var rememberDocumentWindowSize: Bool

    @Stored(key: "SBSaveFormat", defaultValue: "m4v")
    static var saveFormat: String

    @Stored(key: "defaultSaveFormat", defaultValue: 0)
    static var defaultSaveFormat: Int

    @Stored(key: "SBOrganizeAlternateGroups", defaultValue: true)
    static var organizeAlternateGroups: Bool

    @Stored(key: "SBInferMediaCharacteristics", defaultValue: true)
    static var inferMediaCharacteristics: Bool

    @Stored(key: "SBAudioMixdown", defaultValue: 1)
    static var audioMixdown: UInt

    @Stored(key: "SBAudioBitrate", defaultValue: 96)
    static var audioBitrate: UInt

    @Stored(key: "SBAudioDRC", defaultValue: 0)
    static var audioDRC: Float

    @Stored(key: "SBAudioConvertAC3", defaultValue: true)
    static var audioConvertAC3: Bool

    @Stored(key: "SBAudioKeepAC3", defaultValue: true)
    static var audioKeepAC3: Bool

    @Stored(key: "SBAudioConvertDts", defaultValue: true)
    static var audioConvertDts: Bool

    @Stored(key: "SBAudioDtsOptions", defaultValue: 0)
    static var audioDtsOptions: UInt

    @Stored(key: "SBSubtitleConvertBitmap", defaultValue: true)
    static var subtitleConvertBitmap: Bool

    @Stored(key: "SBRatingsCountry", defaultValue: "All countries")
    static var ratingsCountry: String

    @Stored(key: "SBChaptersPreviewPosition", defaultValue: 0.5)
    static var chaptersPreviewPosition: Float

    @Stored(key: "chaptersPreviewTrack", defaultValue: true)
    static var chaptersPreviewTrack: Bool

    @Stored(key: "mp464bitOffset", defaultValue: true)
    static var mp464bitOffset: Bool

    @Stored(key: "mp464bitTimes", defaultValue: false)
    static var mp464bitTimes: Bool

    @Stored(key: "mp4SaveAsOptimize", defaultValue: false)
    static var mp4SaveAsOptimize: Bool

    @Stored(key: "SBForceHvc1", defaultValue: true)
    static var forceHvc1: Bool
}

struct MetadataPrefs {

    static func register() {
        var defaults = [String : Any]()
        ([_setMovieFormat, _setTVShowFormat,
          _movieImporter, _movieiTunesStoreLanguage,
          _tvShowImporter, _tvShowiTunesStoreLanguage, _tvShowTheTVDBLanguage, _tvShowTheMovieDBLanguage,
          _keepEmptyAnnotations, _keepImportedFilesMetadata]
            as? [Registable])?
            .forEach { $0.registerDefault(in: &defaults) }

        ud.register(defaults: defaults)
    }

    @StoredCodable(key: "SBMovieFormatTokens", defaultValue: [Token(text: "{Name}")])
    static var movieFormatTokens: [Token]

    @StoredCodable(key: "SBTVShowFormatTokens", defaultValue: [Token(text: "{TV Show}"), Token(text: " s", isPlaceholder: false), Token(text: "{TV Season}"), Token(text: "e", isPlaceholder: false), Token(text: "{TV Episode #}")])
    static var tvShowFormatTokens: [Token]


    @Stored(key: "SBSetMovieFormat", defaultValue: false)
    static var setMovieFormat: Bool

    @Stored(key: "SBSetTVShowFormat", defaultValue: false)
    static var setTVShowFormat: Bool


    @Stored(key: "SBMetadataPreference|Movie", defaultValue: "TheMovieDB")
    static var movieImporter: String

    @Stored(key: "SBMetadataPreference|Movie|iTunes Store|Language", defaultValue: "USA (English)")
    static var movieiTunesStoreLanguage: String

    @Stored(key: "SBMetadataPreference|Movie|TheMovieDB|Language", defaultValue: "en")
    static var movieLanguage: String


    @Stored(key: "SBMetadataPreference|TV", defaultValue: "TheTVDB")
    static var tvShowImporter: String

    @Stored(key: "SBMetadataPreference|TV|iTunes Store|Language", defaultValue: "USA (English)")
    static var tvShowiTunesStoreLanguage: String

    @Stored(key: "SBMetadataPreference|TV|TheTVDB|Language", defaultValue: "en")
    static var tvShowTheTVDBLanguage: String

    @Stored(key: "SBMetadataPreference|TV|TheMovieDB|Language", defaultValue: "en")
    static var tvShowTheMovieDBLanguage: String


    @StoredCodable(key: "SBMetadataMovieResultMap2", defaultValue: MetadataResultMap.movieDefaultMap)
    static var movieResultMap: MetadataResultMap

    @StoredCodable(key: "SBMetadataTvShowResultMap2", defaultValue: MetadataResultMap.tvShowDefaultMap)
    static var tvShowResultMap: MetadataResultMap

    @Stored(key: "SBMetadataKeepEmptyAnnotations", defaultValue: false)
    static var keepEmptyAnnotations: Bool

    @Stored(key: "SBFileImporterImportMetadata", defaultValue: false)
    static var keepImportedFilesMetadata: Bool
}