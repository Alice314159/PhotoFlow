import Foundation

/// Parsed search text. Space-separated terms must all match ("鸟 上海 2024").
/// Each term is checked against file and folder names, camera and lens, content groups and labels
/// (with Chinese / English synonyms), place names, and the capture date.
struct SearchQuery {
    struct Term {
        let text: String
        let categories: Set<PhotoCategory>
        /// Vision identifiers this term stands for (e.g. 狗 → dog, canine).
        let labels: Set<String>
        let hasDigit: Bool
    }

    let terms: [Term]

    var isEmpty: Bool { terms.isEmpty }

    init(_ raw: String) {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，;；、"))
        terms = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            .map(Self.makeTerm)
    }

    func matches(_ photo: PhotoItem) -> Bool {
        terms.allSatisfy { Self.term($0, matches: photo) }
    }

    private static func makeTerm(_ text: String) -> Term {
        var categories = Set<PhotoCategory>()
        for category in PhotoCategory.allCases where category != .other {
            if category.chineseTitle.lowercased().contains(text)
                || category.englishTitle.lowercased().contains(text)
                || categoryAliases[category, default: []].contains(where: { $0 == text || (text.count > 1 && $0.contains(text)) }) {
                categories.insert(category)
            }
        }
        var labels = Set<String>()
        for (word, identifiers) in labelSynonyms where word == text || (text.count > 1 && word.contains(text)) {
            labels.formUnion(identifiers)
        }
        return Term(text: text, categories: categories, labels: labels, hasDigit: text.contains(where: \.isNumber))
    }

    private static func term(_ term: Term, matches photo: PhotoItem) -> Bool {
        let text = term.text
        if nearbyPath(photo).contains(text) { return true }
        if photo.cameraDisplayName.lowercased().contains(text) || photo.lensDisplayName.lowercased().contains(text) {
            return true
        }
        if !term.categories.isDisjoint(with: photo.categories) { return true }
        for label in photo.contentLabels {
            if term.labels.contains(label) { return true }
            if text.count > 2, label.split(separator: "_").contains(where: { $0.hasPrefix(text) }) { return true }
        }
        if let place = photo.placeText, place.lowercased().contains(text) { return true }
        if term.hasDigit, let date = photo.createdDate ?? photo.fileModificationDate {
            return dateStrings(date).contains { $0.contains(text) }
        }
        return false
    }

    /// File name plus the two enclosing folders ("2024 上海/Day 2/DSC0001.JPG"); higher folders would match everything.
    private static func nearbyPath(_ photo: PhotoItem) -> String {
        photo.url.pathComponents.suffix(3).joined(separator: "/").lowercased()
    }

    private static let dateFormatters: [DateFormatter] = ["yyyy-MM-dd", "yyyy年M月d日", "yyyy.M.d", "yyyyMMdd"].map {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = $0
        return formatter
    }

    private static func dateStrings(_ date: Date) -> [String] {
        dateFormatters.map { $0.string(from: date) }
    }

    // MARK: - Vocabulary

    private static let categoryAliases: [PhotoCategory: [String]] = [
        .people: ["人", "人物", "人像", "肖像", "合影", "合照", "自拍", "模特", "portrait", "person", "people", "human", "face", "model"],
        .sports: ["运动", "体育", "比赛", "竞技", "赛事", "球赛", "sport", "game", "match", "athlete"],
        .pets: ["宠物", "猫", "狗", "小猫", "小狗", "猫咪", "狗狗", "pet", "puppy", "kitty"],
        .birds: ["鸟", "飞鸟", "鸟类", "bird", "birding"],
        .animals: ["动物", "野生动物", "野生", "wildlife", "animal", "zoo"],
        .nature: ["风景", "风光", "自然", "景色", "山水", "户外", "大自然", "landscape", "scenery", "scenic", "outdoor"],
        .flowers: ["花", "花卉", "鲜花", "植物", "花朵", "flower", "plant", "bloom"],
        .architecture: ["建筑", "城市", "街道", "街拍", "楼", "城景", "人文", "city", "street", "urban", "building"],
        .food: ["美食", "食物", "吃", "菜", "饮品", "饮料", "甜点", "food", "meal", "dish", "drink"],
        .vehicles: ["车", "汽车", "交通", "飞机", "船", "火车", "vehicle", "transport", "car"],
        .night: ["夜景", "夜晚", "晚上", "夜", "星空", "银河", "night", "astro", "stars"],
        .events: ["活动", "婚礼", "演出", "音乐会", "派对", "庆典", "聚会", "舞台", "毕业", "event", "party", "concert", "wedding"],
        .documents: ["文档", "截图", "文件", "票据", "document", "screenshot", "receipt"],
    ]

    /// Chinese (and a few English) words → Vision identifiers.
    private static let labelSynonyms: [String: Set<String>] = [
        "狗": ["dog", "canine"], "小狗": ["dog", "canine"], "puppy": ["dog", "canine"],
        "猫": ["cat", "kitten", "adult_cat", "feline"], "小猫": ["kitten", "cat"],
        "鸟": ["bird"], "鹰": ["eagle", "raptor", "peregrine"], "猫头鹰": ["owl"], "鹦鹉": ["parrot", "cockatoo", "parakeet"],
        "企鹅": ["penguin"], "天鹅": ["swan"], "鸽子": ["pigeon", "dove"], "海鸥": ["gull"], "鹭": ["heron"],
        "孔雀": ["peacock"], "火烈鸟": ["flamingo"], "蜂鸟": ["hummingbird"], "鹈鹕": ["pelican"],
        "马": ["horse", "equestrian"], "牛": ["cow"], "羊": ["sheep", "goat"], "猪": ["pig"], "兔": ["rabbit"],
        "鱼": ["fish", "goldfish", "koi"], "蝴蝶": ["butterfly"], "蜜蜂": ["bee"], "昆虫": ["insect"],
        "熊": ["bear"], "熊猫": ["panda"], "鹿": ["deer", "elk", "moose"], "狮子": ["lion"], "老虎": ["tiger"],
        "大象": ["elephant"], "长颈鹿": ["giraffe"], "斑马": ["zebra"], "狐狸": ["fox"], "松鼠": ["squirrel"],
        "海豚": ["dolphin"], "鲸": ["whale", "cetacean"], "乌龟": ["turtle", "tortoise"], "蛇": ["snake"],
        "山": ["mountain", "hill", "cliff"], "高山": ["mountain"], "海": ["ocean", "shore", "water_body"],
        "海边": ["beach", "shore", "ocean", "coast"], "海滩": ["beach", "sand"], "沙滩": ["beach", "sand"],
        "湖": ["lake"], "河": ["river", "creek", "waterways"], "瀑布": ["waterfall"], "水": ["water", "water_body"],
        "雪": ["snow", "blizzard"], "冰": ["ice", "glacier", "iceberg"], "沙漠": ["desert", "sand_dune"],
        "森林": ["forest", "jungle"], "树": ["tree", "maple_tree", "oak_tree", "palm_tree", "evergreen"],
        "草": ["grass"], "草地": ["grass", "land"], "天空": ["sky", "blue_sky"], "蓝天": ["blue_sky"], "云": ["cloudy", "sky"],
        "日落": ["sunset_sunrise"], "日出": ["sunset_sunrise"], "夕阳": ["sunset_sunrise"], "黄昏": ["sunset_sunrise"],
        "彩虹": ["rainbow"], "极光": ["aurora"], "闪电": ["lightning"], "雾": ["haze"], "火山": ["volcano"], "岛": ["island"],
        "花": ["flower", "blossom"], "玫瑰": ["rose"], "郁金香": ["tulip"], "樱花": ["blossom"], "向日葵": ["sunflower"],
        "荷花": ["lily"], "菊花": ["chrysanthemum"], "兰花": ["orchid"], "仙人掌": ["cactus"], "蘑菇": ["mushroom"],
        "花园": ["garden"], "公园": ["park"], "叶子": ["foliage"], "红叶": ["maple_tree", "foliage"],
        "建筑": ["building", "structure"], "大楼": ["building", "skyscraper"], "摩天楼": ["skyscraper"],
        "桥": ["bridge"], "塔": ["tower", "clock_tower", "belltower"], "城堡": ["castle"], "灯塔": ["lighthouse"],
        "雕像": ["statue"], "博物馆": ["museum"], "街": ["street", "alley", "crosswalk"], "城市": ["cityscape"],
        "港口": ["harbour", "pier", "dock"], "室内": ["interior_room"], "厨房": ["kitchen"], "古迹": ["ruins", "monument"],
        "车": ["car", "automobile", "vehicle"], "汽车": ["car", "automobile"], "跑车": ["sportscar"],
        "自行车": ["bicycle", "cycling"], "单车": ["bicycle", "cycling"], "摩托": ["motorcycle"],
        "飞机": ["airplane", "aircraft"], "直升机": ["helicopter"], "船": ["boat", "watercraft", "sailboat", "yacht"],
        "火车": ["train", "train_real"], "公交": ["bus"],
        "足球": ["soccer"], "篮球": ["basketball"], "网球": ["tennis"], "排球": ["volleyball"], "棒球": ["baseball"],
        "高尔夫": ["golf", "golf_course"], "游泳": ["swimming", "diving"], "跑步": ["athletics"], "田径": ["athletics"],
        "滑雪": ["skiing", "snowboarding"], "冲浪": ["surfing"], "骑行": ["cycling"], "拳击": ["boxing", "kickboxing"],
        "体操": ["gymnastics"], "赛车": ["motorsport", "formula_one_car", "nascar", "grand_prix"], "攀岩": ["rock_climbing"],
        "马术": ["equestrian", "dressage"], "滑板": ["skateboarding"], "瑜伽": ["yoga"], "健身": ["workout", "health_club"],
        "婚礼": ["wedding", "bride", "groom", "wedding_dress"], "新娘": ["bride"], "生日": ["birthday_cake"],
        "蛋糕": ["cake", "birthday_cake"], "毕业": ["graduation"], "圣诞": ["christmas_tree", "christmas_decoration", "santa_claus"],
        "烟花": ["fireworks", "firecracker", "pyrotechnics"], "演唱会": ["concert", "singer"], "音乐会": ["concert", "orchestra"],
        "跳舞": ["dancing", "ballet"], "舞蹈": ["dancing", "ballet"],
        "婴儿": ["baby"], "宝宝": ["baby"], "孩子": ["child"], "儿童": ["child"], "小孩": ["child"], "人群": ["crowd"],
        "咖啡": ["coffee"], "茶": ["tea_drink"], "酒": ["wine", "beer", "cocktail", "liquor"], "啤酒": ["beer"],
        "水果": ["fruit"], "寿司": ["sushi"], "披萨": ["pizza"], "面": ["pasta", "ramen", "noodles"], "汉堡": ["hamburger"],
        "甜点": ["dessert", "cake", "ice_cream"], "冰淇淋": ["ice_cream"], "火锅": ["soup"],
        "月亮": ["moon"], "星空": ["night_sky"], "夜空": ["night_sky"],
        "书": ["book"], "电脑": ["computer", "laptop"], "手机": ["phone"], "相机": ["camera"], "眼镜": ["eyeglasses"],
        "伞": ["umbrella"], "灯": ["light", "lamp", "lantern"], "三脚架": ["tripod"],
        "sea": ["ocean", "shore"], "seaside": ["beach", "shore"], "sunset": ["sunset_sunrise"], "sunrise": ["sunset_sunrise"],
        "kid": ["child"], "kids": ["child"], "car": ["car", "automobile"], "plane": ["airplane", "aircraft"],
    ]
}
