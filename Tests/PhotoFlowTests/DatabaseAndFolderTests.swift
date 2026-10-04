import Foundation
import Testing
@testable import PhotoFlow

@Suite("Database paths")
struct PhotoDatabaseTests {
    @Test func updatePathMovesMarksAnalysisLocationAndCollection() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoFlow-tests-\(UUID().uuidString)")
            .appendingPathComponent("photoflow.sqlite")
        let db = PhotoDatabase(fileURL: url)
        #expect(db.isAvailable)

        var photo = PhotoItem(filePath: "/tmp/old/IMG_1.jpg")
        photo.rating = 4
        photo.colorLabel = .red
        photo.pickStatus = .picked
        db.save(photo)
        db.saveAnalyses([(
            path: photo.filePath,
            categories: [.birds],
            labels: ["bird"],
            faceCount: 0,
            version: PhotoClassifier.version,
            manual: false
        )])
        db.saveLocations([(
            path: photo.filePath,
            location: .init(latitude: 31.2, longitude: 121.5, placeName: "上海", placeText: "上海"),
            manual: false
        )])
        let collectionID = try #require(db.createCollection(named: "Trip"))
        db.addToCollection(collectionID, paths: [photo.filePath])

        db.updatePaths([(photo.filePath, "/tmp/new/Keep.jpg")])

        #expect(db.annotations(for: [photo.filePath]).isEmpty)
        let moved = try #require(db.annotations(for: ["/tmp/new/Keep.jpg"])["/tmp/new/Keep.jpg"])
        #expect(moved.rating == 4)
        #expect(moved.colorLabel == .red)
        #expect(moved.pickStatus == .picked)

        let analysis = try #require(db.analyses(for: ["/tmp/new/Keep.jpg"])["/tmp/new/Keep.jpg"])
        #expect(analysis.categories == [.birds])

        let location = try #require(db.locations(for: ["/tmp/new/Keep.jpg"])["/tmp/new/Keep.jpg"])
        #expect(location.placeName == "上海")

        let collection = try #require(db.loadCollections().first { $0.id == collectionID })
        #expect(collection.paths == ["/tmp/new/Keep.jpg"] as Set)

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

@Suite("Folder diff")
struct FolderDiffTests {
    @Test func detectsAddedRemovedAndStale() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        var kept = PhotoItem(filePath: "/folder/kept.jpg")
        kept.fileModificationDate = oldDate
        var gone = PhotoItem(filePath: "/folder/gone.jpg")
        gone.fileModificationDate = oldDate
        var stale = PhotoItem(filePath: "/folder/stale.jpg")
        stale.fileModificationDate = oldDate

        let scanned = [
            ScannedFile(url: URL(fileURLWithPath: "/folder/kept.jpg"), modificationDate: oldDate, fileSize: 10),
            ScannedFile(url: URL(fileURLWithPath: "/folder/stale.jpg"), modificationDate: newDate, fileSize: 12),
            ScannedFile(url: URL(fileURLWithPath: "/folder/new.jpg"), modificationDate: newDate, fileSize: 8),
        ]

        let diff = FolderDiff.between(known: [kept, gone, stale], scanned: scanned)
        #expect(diff.added.map(\.url.lastPathComponent) == ["new.jpg"])
        #expect(diff.removedIDs == ["/folder/gone.jpg"])
        #expect(diff.staleDates["/folder/stale.jpg"] == newDate)
        #expect(diff.staleDates["/folder/kept.jpg"] == nil)
    }

    @Test func emptyWhenNothingChanged() {
        var photo = PhotoItem(filePath: "/a.jpg")
        photo.fileModificationDate = Date(timeIntervalSince1970: 5)
        let scanned = [ScannedFile(url: URL(fileURLWithPath: "/a.jpg"), modificationDate: Date(timeIntervalSince1970: 5.4), fileSize: 1)]
        #expect(FolderDiff.between(known: [photo], scanned: scanned).isEmpty)
    }
}
