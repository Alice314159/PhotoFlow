import Foundation
import Testing
@testable import PhotoFlow

private func photo(
    _ path: String,
    rating: Int = 0,
    pick: PickStatus = .none,
    color: ColorLabel = .none,
    categories: Set<PhotoCategory> = [],
    labels: [String] = [],
    place: String? = nil,
    date: String? = nil
) -> PhotoItem {
    var item = PhotoItem(filePath: path)
    item.rating = rating
    item.pickStatus = pick
    item.colorLabel = color
    item.categories = categories
    item.contentLabels = labels
    item.placeName = place
    item.placeText = place
    if let date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        item.createdDate = formatter.date(from: date)
    }
    return item
}

@Suite("Search")
struct SearchQueryTests {
    let bird = photo("/Trips/Shanghai/IMG_1.jpg", categories: [.birds], labels: ["bird", "sky"], place: "上海", date: "2024-10-02")
    let dog = photo("/Home/IMG_2.jpg", categories: [.pets], labels: ["dog"], date: "2023-05-01")
    let landscape = photo("/Trips/Yosemite/IMG_3.jpg", categories: [.nature], labels: ["mountain"], place: "约塞米蒂国家公园")

    @Test("Chinese and English content words", arguments: [
        ("鸟", true), ("bird", true), ("狗", false), ("风景", false),
    ])
    func content(term: String, matchesBird: Bool) {
        #expect(SearchQuery(term).matches(bird) == matchesBird)
    }

    @Test func synonymsFindTheDog() {
        #expect(SearchQuery("狗").matches(dog))
        #expect(SearchQuery("宠物").matches(dog))
    }

    @Test func landscapeMatchesNature() {
        #expect(SearchQuery("风景").matches(landscape))
    }

    @Test func allTermsMustMatch() {
        #expect(SearchQuery("鸟 上海").matches(bird))
        #expect(!SearchQuery("鸟 北京").matches(bird))
    }

    @Test func datesAndFolders() {
        #expect(SearchQuery("2024-10").matches(bird))
        #expect(SearchQuery("2024年10月").matches(bird))
        #expect(!SearchQuery("2024").matches(dog))
        #expect(SearchQuery("yosemite").matches(landscape))
    }

    @Test func separatorsIncludeChinesePunctuation() {
        #expect(SearchQuery("鸟，上海").terms.count == 2)
        #expect(SearchQuery("  ").isEmpty)
    }
}

@Suite("Filters")
struct FilterStateTests {
    @Test func groupsCombineWithOr() {
        var filter = FilterState()
        filter.selectedCategories = [.pets, .birds]
        #expect(filter.matches(photo("/a.jpg", categories: [.pets])))
        #expect(filter.matches(photo("/b.jpg", categories: [.birds])))
        #expect(!filter.matches(photo("/c.jpg", categories: [.food])))
    }

    @Test func dependsOnMarksOnlyForMarkFilters() {
        var filter = FilterState()
        #expect(!filter.dependsOnMarks)
        filter.selectedCategories = [.people]
        #expect(!filter.dependsOnMarks)
        filter.minimumRating = 3
        #expect(filter.dependsOnMarks)
        filter.minimumRating = 0
        filter.selectedPicks = [.picked]
        #expect(filter.dependsOnMarks)
    }

    @Test func markCounts() {
        let counts = MarkCounts([
            photo("/1.jpg", rating: 5, pick: .picked, color: .red),
            photo("/2.jpg", rating: 4, pick: .picked),
            photo("/3.jpg", rating: 2, pick: .rejected, color: .red),
            photo("/4.jpg"),
        ])
        #expect(counts.atLeast[0] == 4)
        #expect(counts.atLeast[4] == 2)
        #expect(counts.atLeast[5] == 1)
        #expect(counts.picks[.picked] == 2)
        #expect(counts.picks[.rejected] == 1)
        #expect(counts.colors[.red] == 2)
    }

    @Test func sortsThatDependOnMarks() {
        #expect(PhotoSort.rating.dependsOnMarks)
        #expect(PhotoSort.pickStatus.dependsOnMarks)
        #expect(!PhotoSort.filename.dependsOnMarks)
        #expect(!PhotoSort.captureDate.dependsOnMarks)
    }
}

@Suite("Exposure values")
struct ExposureFormatTests {
    @Test(arguments: [
        ("1/500", 0.002), ("1/500s", 0.002), ("2s", 2.0), ("0.5", 0.5), ("1/8000 sec", 0.000125),
    ])
    func shutter(raw: String, seconds: Double) throws {
        let value = try #require(ExposureFormat.parseShutterString(raw))
        #expect(abs(value - seconds) < 1e-9)
    }

    @Test func labels() {
        #expect(ExposureFormat.shutterLabel(0.002) == "1/500")
        #expect(ExposureFormat.shutterLabel(2) == "2s")
        #expect(ExposureFormat.apertureLabel(2.8) == "f/2.8")
        #expect(ExposureFormat.apertureLabel(8) == "f/8")
    }
}
