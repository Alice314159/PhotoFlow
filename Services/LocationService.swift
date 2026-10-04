import CoreLocation
import Foundation
import ImageIO

enum LocationService {
    /// Reads GPS coordinates from the file's metadata (no pixels are decoded).
    static func coordinate(of url: URL) -> CLLocationCoordinate2D? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              var longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
        else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" { longitude = -longitude }
        guard abs(latitude) <= 90, abs(longitude) <= 180, !(latitude == 0 && longitude == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Photos within roughly a kilometre share one lookup.
    static func cell(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }

    /// Reverse-geocodes in Chinese and English so either language finds the photo.
    /// Uses Apple's geocoding service; only the coordinate is sent.
    static func placeNames(for coordinate: CLLocationCoordinate2D) async throws -> (name: String, text: String)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let chinese = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_Hans_CN")).first
        try await Task.sleep(for: .milliseconds(400))
        let english = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first

        let marks = [chinese, english].compactMap { $0 }
        guard let primary = marks.first else { return nil }
        var parts: [String] = []
        for mark in marks {
            let fields: [String?] = [mark.name] + (mark.areasOfInterest ?? []).map(Optional.some) + [
                mark.subLocality, mark.locality, mark.subAdministrativeArea, mark.administrativeArea,
                mark.country, mark.inlandWater, mark.ocean,
            ]
            for case let field? in fields where !field.isEmpty && !parts.contains(field) {
                parts.append(field)
            }
        }
        // In parks the "locality" is often an obscure nearby town; the park is what people search for.
        let landmarkHints = ["公园", "国家", "风景", "景区", "山", "湖", "岛", "Park", "National", "Lake", "Island", "Mount"]
        let landmark = primary.areasOfInterest?.first { area in landmarkHints.contains { area.contains($0) } }
        let name = landmark ?? primary.locality ?? primary.subAdministrativeArea ?? primary.administrativeArea
            ?? primary.areasOfInterest?.first ?? primary.name ?? primary.country
        guard let name else { return nil }
        return (name, parts.joined(separator: " · "))
    }
}
