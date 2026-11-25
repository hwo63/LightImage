import XCTest
import CoreImage
@testable import LightImageCore

final class AdvancedPresetTests: XCTestCase {
    func preset(_ attributes: String) throws -> PhotoPreset {
        let xml = "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:crs=\"http://ns.adobe.com/camera-raw-settings/1.0/\" \(attributes)/></rdf:RDF>"
        return try PresetParser.parse(data: Data(xml.utf8), filename: "test.xmp")
    }
    func testNewParametersAreRetainedAndRealLimitationsRemain() throws {
        let p = try preset("""
            crs:RedHue="41" crs:BlueSaturation="46" crs:ParametricDarks="5" crs:ParametricShadowSplit="25"
            crs:SplitToningShadowHue="44" crs:SplitToningShadowSaturation="14" crs:ColorGradeBlending="50"
            crs:Dehaze="3" crs:AutoTone="True" crs:SharpenRadius="1.0" crs:ColorNoiseReduction="10"
            crs:PerspectiveScale="100" crs:PerspectiveX="0.00" crs:PerspectiveY="-0.0"
            crs:DefringePurpleAmount="0" crs:DefringePurpleHueLo="30" crs:DefringePurpleHueHi="70"
            crs:AutoLateralCA="1" crs:LensProfileEnable="1" crs:LensProfileSetup="LensDefaults" crs:CameraProfile="Default Color"
            """)
        XCTAssertEqual(p.settings["RedHue"], 41); XCTAssertEqual(p.settings["AutoTone"], 1)
        XCTAssertEqual(p.settings["ColorNoiseReduction"], 10)
        XCTAssertEqual(p.unsupported, ["AutoLateralCA", "CameraProfile", "LensProfileEnable", "LensProfileSetup"])
        XCTAssertNotNil(p.sourceData); XCTAssertEqual(p.parserVersion, PresetParser.version)
        let activeFringe = try preset("crs:DefringePurpleAmount=\"5\" crs:DefringePurpleHueLo=\"30\"")
        XCTAssertTrue(activeFringe.unsupported.contains("DefringePurpleAmount"))
        XCTAssertTrue(activeFringe.unsupported.contains("DefringePurpleHueLo"))
        let zero = try preset("crs:Exposure2012=\"0\" crs:Unrecognized=\"+0.00\" crs:LensProfileEnable=\"0\" crs:LensProfileSetup=\"LensDefaults\"")
        XCTAssertTrue(zero.unsupported.isEmpty)
        XCTAssertThrowsError(try preset("crs:AutoTone=\"maybe\""))
    }
    func testDefaultsAndIntensityDoNotZoomOrRotateHueTheLongWay() throws {
        var base = Adjustments(); base["SplitToningShadowHue"] = 350
        let p = try preset("crs:PerspectiveScale=\"120\" crs:SplitToningShadowHue=\"10\" crs:SplitToningShadowSaturation=\"20\" crs:AutoTone=\"False\"")
        base.apply(p, amount: 0.5)
        XCTAssertEqual(base["PerspectiveScale"],110); XCTAssertEqual(base["SplitToningShadowHue"],0,accuracy:0.001)
        var defaults = Adjustments(); defaults.values = PresetParameters.defaults
        XCTAssertFalse(defaults.isEdited)
        let legacy = try preset("crs:SplitToningShadowSaturation=\"10\"")
        XCTAssertEqual(legacy.settings["ColorGradeBlending"],100)
    }
    func testReimportUpgradesPresetInPlaceAndRoundTripsOriginalData() throws {
        var c = Catalog(); var old = try preset("crs:Exposure2012=\"0.2\"")
        old.sourceData = nil; old.parserVersion = nil
        c.presets = [old]; c.photos = [PhotoRecord(path: "/tmp/original.jpg")]
        let upgraded = try preset("crs:Exposure2012=\"0.2\" crs:RedHue=\"41\"")
        XCTAssertFalse(c.mergePreset(upgraded)); XCTAssertEqual(c.presets.count,1)
        XCTAssertEqual(c.presets[0].id,old.id); XCTAssertEqual(c.photos[0].adjustments,Adjustments())
        let decoded = try JSONDecoder().decode(Catalog.self,from:JSONEncoder().encode(c))
        let reparse = try PresetParser.parse(data:XCTUnwrap(decoded.presets[0].sourceData),filename:decoded.presets[0].source)
        XCTAssertEqual(reparse.settings["RedHue"],41)
    }
    func testCalibrationAffectsColorsButKeepsNeutralGrays() {
        var a = Adjustments(); a["RedHue"] = 41; a["GreenHue"] = 77; a["BlueSaturation"] = 46; a["RedSaturation"] = -28
        let treatment = ColorTreatment(a), input = SIMD3(0.75,0.46,0.3)
        let edited = treatment.transform(input)
        XCTAssertGreaterThan(distance(input,edited),0.01)
        for value in [0.1,0.3,0.5,0.8] {
            let out = treatment.transform(SIMD3(repeating:value))
            XCTAssertEqual(out.x,out.y,accuracy:1e-6); XCTAssertEqual(out.y,out.z,accuracy:1e-6)
        }
    }
    func testParametricDarksAndSplitPositionsAffectTheirToneRegions() {
        var a = Adjustments(); a["ParametricDarks"] = 50
        let dark = ColorTreatment(a).transform(SIMD3(repeating:0.35)).x
        let highlight = ColorTreatment(a).transform(SIMD3(repeating:0.9)).x
        XCTAssertGreaterThan(dark,0.4); XCTAssertEqual(highlight,0.9,accuracy:0.002)
        a["ParametricShadowSplit"] = 45
        XCTAssertLessThan(ColorTreatment(a).transform(SIMD3(repeating:0.35)).x,dark)
    }
    func testGradingTintsShadowsAndHighlightsIncludingMonochrome() {
        var a = Adjustments(); a.monochrome = true
        a["SplitToningShadowHue"] = 44; a["SplitToningShadowSaturation"] = 60
        a["SplitToningHighlightHue"] = 215; a["SplitToningHighlightSaturation"] = 60
        let treatment = ColorTreatment(a)
        let shadow = treatment.transform(SIMD3(repeating:0.15)), highlight = treatment.transform(SIMD3(repeating:0.85))
        XCTAssertGreaterThan(shadow.x,shadow.z); XCTAssertGreaterThan(highlight.z,highlight.x)
        a["ColorGradeBlending"] = 0
        let narrow = ColorTreatment(a).transform(SIMD3(repeating:0.5))
        a["ColorGradeBlending"] = 100
        XCTAssertGreaterThan(distance(narrow,ColorTreatment(a).transform(SIMD3(repeating:0.5))),0.01)
        let center = ColorTreatment(a).transform(SIMD3(repeating:0.4))
        a["SplitToningBalance"] = 100
        XCTAssertGreaterThan(distance(center,ColorTreatment(a).transform(SIMD3(repeating:0.4))),0.01)
        XCTAssertEqual(treatment.transform(.zero),.zero)
        XCTAssertEqual(treatment.transform(SIMD3(repeating:1)),SIMD3(repeating:1))
    }
    func testCubicCurvePassesPointsAndNeverOvershoots() {
        let points: [CurvePoint] = [.init(0,0.01),.init(0.13,0.21),.init(0.24,0.38),.init(0.68,0.78),.init(1,1)]
        for p in points { XCTAssertEqual(ImageEngine.curve(p.x,points),p.y,accuracy:1e-9) }
        let samples = (0...1000).map { ImageEngine.curve(Double($0)/1000,points) }
        XCTAssertTrue(zip(samples,samples.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertTrue(samples.allSatisfy { (0...1).contains($0) })
    }
    func testKernelsAndNoiseReductionPreserveLuminanceAndChangeChroma() throws {
        XCTAssertTrue(AdvancedEffects.kernelsAvailable)
        let engine = ImageEngine(), image = fixture()
        let before = pixels(image,engine)
        var a = Adjustments(); a["ColorNoiseReduction"] = 70; a["ColorNoiseReductionDetail"] = 0
        let after = pixels(try AdvancedEffects.reduceNoise(image,a,pixelScale:1),engine)
        XCTAssertGreaterThan(difference(before,after),0.002)
        XCTAssertLessThan(chromaEnergy(after),chromaEnergy(before))
        let lumError = zip(before,after).map { abs(ColorTreatment.luma($0)-ColorTreatment.luma($1)) }.reduce(0,+)/Double(before.count)
        XCTAssertLessThan(lumError,0.003)
        a["ColorNoiseReductionSmoothness"] = 0
        let lessSmooth = pixels(try AdvancedEffects.reduceNoise(image,a,pixelScale:1),engine)
        XCTAssertGreaterThan(difference(after,lessSmooth),0.0001)
        a["ColorNoiseReduction"] = 0; a["LuminanceSmoothing"] = 70
        let lowDetail = pixels(try AdvancedEffects.reduceNoise(image,a,pixelScale:1),engine)
        a["ColorNoiseReductionSmoothness"] = 100
        XCTAssertLessThan(difference(lowDetail,pixels(try AdvancedEffects.reduceNoise(image,a,pixelScale:1),engine)),0.00001)
    }
    func testSharpenRadiusDetailAndMaskingProduceDifferentResults() throws {
        let engine = ImageEngine(), image = fixture(); var a = Adjustments(); a["Sharpness"] = 100
        let normal = pixels(try AdvancedEffects.sharpen(image,a,pixelScale:1),engine)
        a["SharpenRadius"] = 2.5
        XCTAssertGreaterThan(difference(normal,pixels(try AdvancedEffects.sharpen(image,a,pixelScale:1),engine)),0.0001)
        a["SharpenRadius"] = 1; a["SharpenDetail"] = 100
        XCTAssertGreaterThan(difference(normal,pixels(try AdvancedEffects.sharpen(image,a,pixelScale:1),engine)),0.0001)
        a["SharpenEdgeMasking"] = 100
        let masked = pixels(try AdvancedEffects.sharpen(image,a,pixelScale:1),engine)
        XCTAssertGreaterThan(difference(normal,masked),0.0001)
        a["Sharpness"] = 0
        XCTAssertLessThan(difference(pixels(image,engine),pixels(try AdvancedEffects.sharpen(image,a,pixelScale:1),engine)),1e-6)
    }
    func testAutoToneAndDehazeChangePixelsAndRemainFinite() throws {
        let engine = ImageEngine(), image = fixture(), before = pixels(image,engine)
        let auto = pixels(try AdvancedEffects.automaticTone(image,engine:engine),engine)
        XCTAssertGreaterThan(difference(before,auto),0.01)
        let haze = pixels(try AdvancedEffects.dehaze(image,amount:-50,engine:engine),engine)
        let clear = pixels(try AdvancedEffects.dehaze(image,amount:50,engine:engine),engine)
        XCTAssertGreaterThan(difference(before,haze),0.01); XCTAssertGreaterThan(difference(before,clear),0.01)
        XCTAssertGreaterThan(haze.map(ColorTreatment.luma).reduce(0,+),before.map(ColorTreatment.luma).reduce(0,+))
        for sample in auto+clear+haze { XCTAssertTrue(sample.x.isFinite && sample.y.isFinite && sample.z.isFinite) }
    }
    func testPerspectiveDefaultsAreIdentityAndTranslationMovesPixels() throws {
        let engine = ImageEngine(), image = fixture()
        var a = Adjustments(); a["PerspectiveScale"] = 100; a["PerspectiveX"] = 0
        XCTAssertLessThan(difference(pixels(image,engine),pixels(engine.geometry(image,adjustments:a),engine)),1e-6)
        a["PerspectiveX"] = 10
        XCTAssertGreaterThan(difference(pixels(image,engine),pixels(engine.geometry(image,adjustments:a),engine)),0.01)
        XCTAssertEqual(engine.geometry(image,adjustments:a).extent,image.extent)
    }
    func testActualUserPresetIfProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LIGHTIMAGE_PRESET_FIXTURE"] else { throw XCTSkip("Set LIGHTIMAGE_PRESET_FIXTURE to test the user's local preset without redistributing it.") }
        let p = try PresetParser.parse(url:URL(fileURLWithPath:path))
        XCTAssertEqual(p.name,"TRẮNG HỒNG 3")
        XCTAssertGreaterThan(p.supportedCount,65)
        XCTAssertEqual(p.unsupported,["AutoLateralCA","CameraProfile","LensProfileEnable","LensProfileSetup"])
        let engine = ImageEngine(); var a = Adjustments(); a.apply(p)
        let result = try engine.render(fixture(),adjustments:a)
        XCTAssertNotNil(try engine.cgImage(result))
        print("TRẮNG HỒNG 3: \(p.supportedCount) supported parameters; remaining: \(p.unsupported.joined(separator:", "))")
    }
    private func fixture() -> CIImage {
        let w = 96, h = 64; var data = [Float]()
        for y in 0..<h { for x in 0..<w {
            let base = 0.15+Double(x)/Double(w)*0.5 + (x>48 ? 0.08 : 0)
            let noise = Double((x*13+y*17)%17-8)/140
            let grain = Double((x*19+y*7)%9-4)/120
            data += [Float(base+noise+grain),Float(base-noise*0.3+grain),Float(base+noise*0.03+grain),1]
        } }
        return CIImage(bitmapData:data.withUnsafeBytes { Data($0) },bytesPerRow:w*16,size:CGSize(width:w,height:h),format:.RGBAf,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
    }
    private func pixels(_ image: CIImage, _ engine: ImageEngine) -> [SIMD3<Double>] {
        let w = 96,h = 64; var data = [Float](repeating:0,count:w*h*4)
        engine.context.render(image,toBitmap:&data,rowBytes:w*16,bounds:CGRect(x:0,y:0,width:w,height:h),format:.RGBAf,colorSpace:engine.colorSpace)
        return stride(from:0,to:data.count,by:4).map { SIMD3(Double(data[$0]),Double(data[$0+1]),Double(data[$0+2])) }
    }
    private func chromaEnergy(_ pixels: [SIMD3<Double>]) -> Double { pixels.map { abs($0.x-$0.y)+abs($0.z-$0.y) }.reduce(0,+)/Double(pixels.count) }
    private func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { abs(a.x-b.x)+abs(a.y-b.y)+abs(a.z-b.z) }
    private func difference(_ a: [SIMD3<Double>], _ b: [SIMD3<Double>]) -> Double { zip(a,b).map { distance($0,$1) }.reduce(0,+)/Double(a.count) }
}
