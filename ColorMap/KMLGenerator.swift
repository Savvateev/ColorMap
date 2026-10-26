import Foundation

struct KMLPlacemark {
    let name: String
    let address: String
    let details: String
    let styleID: String
    let coordinate: GeocodedCoordinate
}

enum KMLGenerator {
    static func generate(placemarks: [KMLPlacemark]) -> String {
        let styles = [
            style(id: "residential-ordinary", icon: "grn-circle.png", scale: 0.85),
            style(id: "residential-disconnected", icon: "ylw-circle.png", scale: 0.85),
            style(id: "residential-deleted", icon: "blk-circle.png", scale: 0.85),
            style(id: "residential-other", icon: "wht-circle.png", scale: 0.85),
            style(id: "mkd-black", icon: "blk-circle.png", scale: 1.5),
            style(id: "mkd-red", icon: "red-circle.png", scale: 1.5),
            style(id: "mkd-yellow", icon: "ylw-circle.png", scale: 1.5),
            style(id: "mkd-green", icon: "grn-circle.png", scale: 1.5)
        ].joined(separator: "\n")

        let placemarkXML = placemarks.map { placemark in
            let longitude = String(
                format: "%.8f",
                locale: Locale(identifier: "en_US_POSIX"),
                placemark.coordinate.longitude
            )
            let latitude = String(
                format: "%.8f",
                locale: Locale(identifier: "en_US_POSIX"),
                placemark.coordinate.latitude
            )

            return """
            <Placemark>
              <name>\(escapeXML(placemark.name))</name>
              <description>\(escapeXML(placemark.details))</description>
              <styleUrl>#\(escapeXML(placemark.styleID))</styleUrl>
              <Point><coordinates>\(longitude),\(latitude),0</coordinates></Point>
            </Placemark>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>ColorMap — дома и проникновение</name>
            \(styles)
            \(placemarkXML)
          </Document>
        </kml>
        """
    }

    static func styleID(forResidentialStatus status: String) -> String {
        switch normalizedStatus(status) {
        case "обычный":
            return "residential-ordinary"
        case "отключен":
            return "residential-disconnected"
        case "удален":
            return "residential-deleted"
        default:
            return "residential-other"
        }
    }

    static func styleID(forPenetration penetration: Double) -> String {
        if penetration == 0 {
            return "mkd-black"
        } else if penetration < 30 {
            return "mkd-red"
        } else if penetration < 60 {
            return "mkd-yellow"
        } else {
            return "mkd-green"
        }
    }

    private static func style(id: String, icon: String, scale: Double) -> String {
        """
        <Style id="\(id)">
          <IconStyle><scale>\(scale)</scale><Icon><href>https://maps.google.com/mapfiles/kml/paddle/\(icon)</href></Icon></IconStyle>
          <LabelStyle><scale>0.8</scale></LabelStyle>
        </Style>
        """
    }

    private static func normalizedStatus(_ status: String) -> String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
