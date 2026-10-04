import CoreGraphics
import Foundation
import ImageIO
import Vision

struct PhotoAnalysis: Sendable {
    var categories: Set<PhotoCategory>
    /// Vision identifiers above the reporting threshold, most confident first.
    var labels: [String]
    var faceCount: Int
}

/// Groups photos by content using Vision on a small decoded copy. Never writes to the file.
enum PhotoClassifier {
    /// Bump when the rules change so stored results are recomputed.
    static let version = 1

    private static let analysisSize = 512
    private static let defaultThreshold: Float = 0.3
    /// Parent labels that show up in a lot of unrelated photos need more confidence.
    private static let broadThreshold: Float = 0.65

    private struct Rule {
        let category: PhotoCategory
        let labels: Set<String>
        var broad: Set<String> = []
        /// Background scenery behind a person shouldn't make a portrait a landscape or architecture shot.
        var broadIgnoredWithPeople = false
    }

    private static let dogBreeds: Set<String> = [
        "dog", "canine", "australian_shepherd", "basenji", "basset", "beagle", "bernese_mountain", "bichon",
        "bulldog", "chihuahua", "collie", "corgi", "dachshund", "dalmatian", "doberman", "german_shepherd",
        "greyhound", "hound", "husky", "irish_wolfhound", "jack_russell_terrier", "malamute", "malinois",
        "mastiff", "newfoundland", "pitbull", "pomeranian", "poodle", "pug", "retriever", "ridgeback",
        "rottweiler", "saint_bernard", "schnauzer", "setter", "sheepdog", "spaniel", "terrier", "vizsla",
        "weimaraner",
    ]

    private static let rules: [Rule] = [
        Rule(category: .people, labels: [
            "people", "adult", "child", "baby", "teen", "crowd", "bride", "groom", "bridesmaid",
        ]),
        Rule(category: .sports, labels: [
            "athletics", "ballgames", "motorsport", "watersport", "winter_sport", "soccer", "basketball",
            "baseball", "football", "tennis", "golf", "golf_course", "hockey", "volleyball", "rugby",
            "cricket_sport", "badminton", "ping_pong", "squash_sport", "softball", "boxing", "kickboxing",
            "martial_arts", "wrestling", "sumo", "fencing_sport", "gymnastics", "cycling", "swimming", "diving",
            "surfing", "skiing", "snowboarding", "skateboarding", "ice_skating", "rink", "equestrian", "dressage",
            "polo", "jockey_horse", "rock_climbing", "rafting", "kayak", "canoe", "formula_one_car", "nascar",
            "motocross", "grand_prix", "stadium", "arena", "scoreboard", "bleachers", "cheerleading", "archery",
            "hurdle", "waterpolo", "windsurfing", "kiteboarding", "wakeboarding", "parasailing", "skydiving",
            "bmx", "puck", "racquet", "rodeo", "bullfighting", "track_rail", "marathon",
        ], broad: ["sport", "sports_equipment", "ball"]),
        Rule(category: .pets, labels: dogBreeds.union([
            "cat", "kitten", "adult_cat", "hamster", "rabbit", "gerbil", "ferret", "chinchilla", "goldfish",
            "guppy", "parakeet", "cockatoo", "leash", "fishbowl", "fishtank",
        ])),
        Rule(category: .birds, labels: [
            "bird", "eagle", "owl", "heron", "gull", "hummingbird", "pelican", "penguin", "flamingo", "peacock",
            "sparrow", "swan", "stork", "toucan", "vulture", "woodpecker", "raven", "pigeon", "dove", "raptor",
            "peregrine", "puffin", "sandpiper", "ostrich", "parrot",
        ]),
        Rule(category: .animals, labels: [
            "deer", "elk", "moose", "bear", "lion", "tiger", "leopard", "cheetah", "cougar", "bobcat", "lynx",
            "elephant", "giraffe", "zebra", "fox", "coyote_wolf", "kangaroo", "koala", "panda", "lemur",
            "rhinoceros", "hippopotamus", "bison", "boar", "squirrel", "raccoon", "otter", "seal", "sealion",
            "walrus", "whale", "dolphin", "cetacean", "shark", "reptile", "snake", "lizard", "insect",
            "butterfly", "dragonfly", "bee", "ladybug", "frog", "turtle", "tortoise", "alligator_crocodile",
            "hyena", "camel", "llama", "horse", "cow", "sheep", "goat", "pig", "donkey", "jellyfish", "fish",
            "marsupial", "ungulates", "arthropods", "chameleon", "iguana", "hedgehog", "porcupine", "skunk",
            "prairie_dog", "zoo", "spider", "moth", "caterpillar",
        ], broad: ["animal", "mammal"]),
        Rule(category: .nature, labels: [
            "mountain", "hill", "cliff", "canyon", "desert", "sand_dune", "beach", "shore", "ocean", "lake",
            "river", "creek", "waterfall", "glacier", "iceberg", "volcano", "forest", "jungle", "blue_sky",
            "sunset_sunrise", "aurora", "rainbow", "snow", "island", "wetland", "geyser", "storm", "lightning",
            "thunderstorm", "mangrove", "cave", "rice_field", "vineyard", "trail", "hiking", "haze", "fog",
            "water_body", "waterways", "valley", "meadow", "maple_tree", "oak_tree", "palm_tree", "evergreen",
            "willow", "sequoia", "eucalyptus_tree", "branch",
        ], broad: ["sky", "cloudy", "land", "grass", "foliage", "vegetation", "tree", "rocks", "sun"], broadIgnoredWithPeople: true),
        Rule(category: .flowers, labels: [
            "flower", "blossom", "rose", "tulip", "lily", "orchid", "daisy", "sunflower", "dahlia", "daffodil",
            "carnation", "chrysanthemum", "cornflower", "marigold", "petunia", "begonia", "poinsettia",
            "snapdragon", "bouquet", "flower_arrangement", "decorative_plant", "cactus", "bonsai", "ferns",
            "moss", "mushroom", "garden", "dandelion", "clover", "ivy", "greenhouse",
        ], broad: ["plant"], broadIgnoredWithPeople: true),
        Rule(category: .architecture, labels: [
            "building", "cityscape", "skyscraper", "bridge", "castle", "tower", "clock_tower", "belltower",
            "monument", "ruins", "dome", "arch", "street", "alley", "storefront", "house_single", "apartment",
            "lighthouse", "pyramid", "museum", "stained_glass", "gargoyle", "obelisk", "megalith", "windmill",
            "crosswalk", "sidewalk", "harbour", "pier", "train_station", "airport", "temple", "church",
        ], broad: ["structure", "roof", "window", "stairs"], broadIgnoredWithPeople: true),
        Rule(category: .food, labels: [
            "food", "dessert", "drink", "baked_goods", "fruit", "vegetable", "meat", "seafood", "cake",
            "coffee", "tea_drink", "cocktail", "wine", "beer", "pizza", "sushi", "pasta", "salad", "soup",
            "sandwich", "hamburger", "noodles", "ramen", "rice", "bread", "steak", "ice_cream",
            "dumpling", "juice", "smoothie", "bubble_tea",
        ], broad: ["tableware", "plate", "bowl"]),
        Rule(category: .vehicles, labels: [
            "automobile", "car", "sportscar", "convertible", "suv", "jeep", "aircraft", "airplane",
            "helicopter", "boat", "sailboat", "yacht", "speedboat", "cruise_ship", "warship", "train",
            "train_real", "streetcar", "tramway", "monorail", "motorcycle", "bus", "truck", "semi_truck",
            "firetruck", "police_car", "ambulance", "limousine", "tractor", "airshow", "rocket", "watercraft",
        ], broad: ["vehicle", "conveyance", "engine_vehicle"]),
        Rule(category: .night, labels: [
            "night_sky", "fireworks", "firecracker", "sparkler", "pyrotechnics", "moon", "celestial_body",
        ]),
        Rule(category: .events, labels: [
            "wedding", "wedding_dress", "wedding_cake", "birthday_cake", "celebration", "ceremony", "concert",
            "performance", "parade", "carnival", "graduation", "christmas_tree", "christmas_decoration",
            "dancing", "ballet", "singer", "orchestra", "nightclub", "theater", "circus", "festival",
            "dragon_parade", "deejay", "conference", "podium",
        ]),
        Rule(category: .documents, labels: [
            "document", "screenshot", "printed_page", "receipt", "handwriting", "diagram", "chart",
            "whiteboard", "chalkboard", "illustrations", "map", "newspaper", "magazine",
        ]),
    ]

    /// nil means Vision itself failed (worth retrying later); undecodable files come back as `.other`.
    static func analyze(url: URL) -> PhotoAnalysis? {
        guard let image = decode(url) else {
            return PhotoAnalysis(categories: [.other], labels: [], faceCount: 0)
        }

        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let animals = VNRecognizeAnimalsRequest()

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([classify, faces, humans, animals])
        } catch {
            return nil
        }

        var confidence: [String: Float] = [:]
        for observation in classify.results ?? [] where observation.confidence >= 0.1 {
            confidence[observation.identifier] = observation.confidence
        }

        // Faces and bodies catch people the scene classifier misses (backs, small figures in sports shots).
        let faceCount = (faces.results ?? []).filter { $0.boundingBox.height >= 0.04 }.count
        let bodyArea = (humans.results ?? []).reduce(CGFloat(0)) { $0 + $1.boundingBox.width * $1.boundingBox.height }
        let peopleLabels = rules.first { $0.category == .people }?.labels ?? []
        let hasPeople = faceCount > 0 || bodyArea >= 0.04
            || peopleLabels.contains { (confidence[$0] ?? 0) >= defaultThreshold }

        var categories = Set<PhotoCategory>()
        if hasPeople { categories.insert(.people) }
        for rule in rules where rule.category != .people {
            let specific = rule.labels.contains { (confidence[$0] ?? 0) >= defaultThreshold }
            let broadAllowed = !(rule.broadIgnoredWithPeople && hasPeople)
            let broad = broadAllowed && rule.broad.contains { (confidence[$0] ?? 0) >= broadThreshold }
            if specific || broad { categories.insert(rule.category) }
        }

        let animalLabels = (animals.results ?? [])
            .filter { $0.confidence >= 0.6 }
            .flatMap(\.labels)
            .map { $0.identifier.lowercased() }
        if animalLabels.contains("dog") || animalLabels.contains("cat") {
            categories.insert(.pets)
        }

        if !categories.contains(.night), averageLuminance(image) < 0.16,
           ["cityscape", "sky", "street", "building", "outdoor", "light", "lamppost"].contains(where: { (confidence[$0] ?? 0) >= 0.3 }) {
            categories.insert(.night)
        }

        if categories.isEmpty { categories = [.other] }

        let labels = confidence
            .filter { $0.value >= 0.2 }
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map(\.key)

        return PhotoAnalysis(categories: categories, labels: Array(labels), faceCount: faceCount)
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        func thumbnail(always: Bool) -> CGImage? {
            let options: [CFString: Any] = [
                always ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: analysisSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        // Embedded previews are much faster for RAW; tiny EXIF thumbnails are too small to classify.
        if let embedded = thumbnail(always: false), max(embedded.width, embedded.height) >= 300 {
            return embedded
        }
        return thumbnail(always: true)
    }

    private static func averageLuminance(_ image: CGImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 1 }
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count) / 255
    }
}
