import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import LightImageCore

// Opt-in local diagnostics. No fixture photos are bundled or uploaded.
let args = CommandLine.arguments
 guard args.count >= 5 else { fatalError("Usage: LightImageDiagnostics input.jpg settings.json|preset.xmp output-directory label [full]") }
let engine = ImageEngine()
let input = URL(fileURLWithPath: args[1])
let settingsURL = URL(fileURLWithPath: args[2])
let data = try Data(contentsOf: settingsURL)
var settings = Adjustments()
if settingsURL.pathExtension.lowercased() == "json" {
    settings = try JSONDecoder().decode(Adjustments.self, from: data)
} else {
    settings.apply(try PresetParser.parse(data: data, filename: settingsURL.lastPathComponent))
}
let directory = URL(fileURLWithPath: args[3]); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
if args.last == "full" {
    try engine.export(url: input, adjustments: settings, destination: directory.appendingPathComponent(args[4]+".jpg"), format: "jpeg")
} else {
    let source = try engine.load(url: input, maxDimension: 960)
    let groups: [(String, (String) -> Bool)] = [
        ("all", { _ in false }), ("calibration", { ["RedHue","GreenHue","BlueHue","RedSaturation","GreenSaturation","BlueSaturation"].contains($0) }),
        ("tone", { ["Shadows2012","Highlights2012","Blacks2012","Whites2012"].contains($0) }),
        ("hsl", { $0.contains("Adjustment") }), ("grade", { $0.hasPrefix("SplitToning") || $0.hasPrefix("ColorGrade") }),
        ("wb", { $0.contains("Temperature") || $0.contains("Tint") }), ("neutral", { _ in true })]
    for (name, predicate) in groups {
        var a = settings; a.values = a.values.filter { !predicate($0.key) }
        if name == "neutral" { a = Adjustments() }
        let cg = try engine.cgImage(engine.render(source, adjustments: a))
        let url = directory.appendingPathComponent(args[4]+"-"+name+".png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG destination") }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("PNG export") }
        print(url.path)
    }
}
