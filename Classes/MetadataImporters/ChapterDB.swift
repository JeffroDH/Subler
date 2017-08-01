//
//  ChapterDB.swift
//  Subler
//
//  Created by Damiano Galassi on 31/07/2017.
//

import Foundation

public struct ChapterDB : ChapterService {

    public func search(title: String, duration: UInt64) -> [ChapterResult] {

        guard let url = URL(string: "http://www.chapterdb.org/chapters/search?title=\(title.urlEncoded())"),
            let data = fetch(url: url)
            else { return [] }

        let parsed = parse(data: data)
        if (duration > 0) {
            let delta: Int64 = 10000
            return parsed.filter { $0.duration < (Int64(duration) + delta) && $0.duration > (Int64(duration) - delta) }
        }
        else {
            return parsed
        }
    }

    private func fetch(url: URL) -> Data? {
        let header = ["ApiKey": "ETET7TXFJH45YNYW0I4A"]
        return SBMetadataHelper.downloadData(from: url, httpMethod: "GET", httpBody: nil, headerOptions: header, cachePolicy: .default)
    }

    private func title(node: XMLNode) -> String? {
        guard let nodes = try? node.nodes(forXPath: "./*:title") else { return nil }
        return nodes.first?.stringValue
    }

    private func confirmations(node: XMLNode) -> UInt? {
        guard let nodes = try? node.nodes(forXPath: "./@confirmations"),
            let confirmations = nodes.first?.stringValue else { return nil }
        return UInt(confirmations)
    }

    private func duration(node: XMLNode) -> UInt64? {
        guard let nodes = try? node.nodes(forXPath: "./*:source/*:duration"),
            let duration = nodes.first?.stringValue else { return nil }
        return TimeFromString(duration, 1000)
    }

    private func parse(node: XMLNode) -> ChapterResult? {
        guard let title = title(node: node),
            let confirmations = confirmations(node: node),
            let duration = duration(node: node),
            let times = try? node.nodes(forXPath: "./*:chapters/*:chapter/@time"),
            let names = try? node.nodes(forXPath: "./*:chapters/*:chapter/@name") else { return nil }

        var currentTime: UInt64 = 0
        var chapters: [Chapter] = Array()

        for (time, name) in zip(times.flatMap { $0.stringValue }, names.flatMap { $0.stringValue }) {
            let timestamp = TimeFromString(time, 1000)

            if timestamp < currentTime {
                break;
            }
            else {
                currentTime = timestamp
            }

            let chapter = Chapter(name: name, timestamp: timestamp)
            chapters.append(chapter)
        }

        if chapters.count > 0 {
            let result = ChapterResult(title: title, duration: duration, confimations: confirmations, chapters: chapters)
            return result
        }

        return nil
    }

    private func parse(data: Data) -> [ChapterResult] {
        guard let document = try? XMLDocument(data: data, options: []),
            let children = try? document.nodes(forXPath: "//*:chapterInfo") else { return [] }

        return children.flatMap { parse(node: $0) }
    }

}