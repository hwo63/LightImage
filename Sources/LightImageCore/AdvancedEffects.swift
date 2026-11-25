import Foundation
import CoreImage

/// Spatial processing shared by preview and full-resolution export.
/// Kernels fail explicitly; no enabled effect silently disappears if a kernel cannot compile.
enum AdvancedEffects {
    private static let denoise = CIColorKernel(source: """
        kernel vec4 denoise(__sample s, __sample b, __sample lb, float lumAmount, float lumDetail, float lumContrast, float colorAmount, float colorDetail) {
            vec3 w = vec3(0.2126, 0.7152, 0.0722);
            float y = dot(s.rgb, w); float by = dot(b.rgb, w);
            float ly = dot(lb.rgb,w); float edge = abs(y-ly);
            float lm = 1.0-smoothstep(0.015+(1.0-lumDetail)*0.12, 0.04+(1.0-lumDetail)*0.22, edge);
            float cm = 1.0-smoothstep(0.025+(1.0-colorDetail)*0.12, 0.08+(1.0-colorDetail)*0.2, length(s.rgb-b.rgb));
            float ny = mix(y, ly, lumAmount*lm*(1.0-lumContrast*0.6));
            vec3 chroma = mix(s.rgb-vec3(y), b.rgb-vec3(by), colorAmount*cm);
            return vec4(clamp(chroma+vec3(ny), 0.0, 1.0), s.a);
        }
        """)
    private static let sharpen = CIColorKernel(source: """
        kernel vec4 sharpen(__sample s, __sample b, __sample fine, __sample edge, float amount, float detail, float masking) {
            vec3 w = vec3(0.2126,0.7152,0.0722);
            float y = dot(s.rgb,w);
            float coarseDelta = y-dot(b.rgb,w); float fineDelta = y-dot(fine.rgb,w);
            float edgeValue = max(edge.r,max(edge.g,edge.b));
            float mask = mix(1.0,smoothstep(0.008+masking*0.08,0.035+masking*0.3,edgeValue),masking);
            float delta = amount*mask*(coarseDelta*(1.0-detail*0.4)+fineDelta*detail*1.5);
            return vec4(clamp(s.rgb+vec3(delta),0.0,1.0),s.a);
        }
        """)
    private static let haze = CIColorKernel(source: """
        kernel vec4 haze(__sample s, __sample dark, float amount, vec3 air) {
            float airY = max(0.5,dot(air,vec3(0.2126,0.7152,0.0722)));
            float transmission = clamp(1.0-amount*0.88*dark.r/airY,0.3,1.0);
            vec3 result = (s.rgb-air)/transmission+air;
            if (amount<0.0) { result = mix(s.rgb,air,-amount*0.55); }
            return vec4(clamp(result,0.0,1.0),s.a);
        }
        """)
    private static let autoTone = CIColorKernel(source: """
        kernel vec4 autoTone(__sample s, float black, float white, float gamma) {
            float y = dot(s.rgb,vec3(0.2126,0.7152,0.0722));
            float target = pow(clamp((y-black)/(white-black),0.0,1.0),gamma);
            // Keep a small shoulder/toe instead of hard-clipping the percentile tails.
            target = mix(y,target,0.85);
            vec3 result = s.rgb * (target/max(y,0.00001));
            return vec4(clamp(result,0.0,1.0),s.a);
        }
        """)
    static var kernelsAvailable: Bool { denoise != nil && sharpen != nil && haze != nil && autoTone != nil }
    private static func apply(_ kernel: CIColorKernel?, to image: CIImage, _ arguments: [Any]) throws -> CIImage {
        guard let output = kernel?.apply(extent: image.extent, arguments: arguments) else {
            throw LightImageError.exportFailed("Core Image không khởi tạo được bộ lọc nâng cao.")
        }
        return output
    }
    static func reduceNoise(_ image: CIImage, _ a: Adjustments, pixelScale: Double) throws -> CIImage {
        guard a["ColorNoiseReduction"] > 0 || a["LuminanceSmoothing"] > 0 else { return image }
        let radius = max(0.25, (0.6 + a["ColorNoiseReductionSmoothness"] / 100 * 3) * pixelScale)
        let blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: image.extent)
        let lumBlur = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.25,(0.6+a["LuminanceSmoothing"]/100*2)*pixelScale)]).cropped(to: image.extent)
        return try apply(denoise, to: image, [image, blurred, lumBlur,
            sqrt(a["LuminanceSmoothing"] / 100), a["LuminanceNoiseReductionDetail"] / 100, a["LuminanceNoiseReductionContrast"] / 100,
            sqrt(a["ColorNoiseReduction"] / 100), a["ColorNoiseReductionDetail"] / 100])
    }
    static func sharpen(_ image: CIImage, _ a: Adjustments, pixelScale: Double) throws -> CIImage {
        guard a["Sharpness"] > 0 else { return image }
        let extended = image.clampedToExtent()
        let blurred = extended.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.1, a["SharpenRadius"] * pixelScale)]).cropped(to: image.extent)
        let fine = extended.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.1, 0.5 * pixelScale)]).cropped(to: image.extent)
        let edges = extended.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1]).cropped(to: image.extent)
        return try apply(sharpen, to: image, [image, blurred, fine, edges, a["Sharpness"] / 100 * 1.8, a["SharpenDetail"] / 100, a["SharpenEdgeMasking"] / 100])
    }
    static func dehaze(_ image: CIImage, amount: Double, engine: ImageEngine) throws -> CIImage {
        guard amount != 0 else { return image }
        let samples = sample(image, engine: engine)
        let bright = samples.sorted { min($0[0],$0[1],$0[2]) > min($1[0],$1[1],$1[2]) }.prefix(max(1,samples.count/100))
        var air = [0.0,0,0]
        for pixel in bright { for c in 0..<3 { air[c] += pixel[c] / Double(bright.count) } }
        air = air.map { min(max($0,0.65),1) }
        let dark = image.clampedToExtent().applyingFilter("CIMinimumComponent")
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(1,max(image.extent.width,image.extent.height)/250)])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(1,max(image.extent.width,image.extent.height)/500)])
            .cropped(to: image.extent)
        return try apply(haze, to: image, [image, dark, amount / 100, CIVector(x: air[0], y: air[1], z: air[2])])
    }
    static func automaticTone(_ image: CIImage, engine: ImageEngine) throws -> CIImage {
        let luminance = sample(image, engine: engine).map { $0[0]*0.2126+$0[1]*0.7152+$0[2]*0.0722 }.sorted()
        guard luminance.count > 10 else { return image }
        let low = luminance[luminance.count/200], high = luminance[luminance.count*199/200]
        guard high-low > 0.02 else { return image }
        let black = min(low,0.1), white = max(high,0.65)
        let median = min(max((luminance[luminance.count/2]-black)/(white-black),0.05),0.95)
        let gamma = min(max(log(0.45)/log(median),0.65),1.4)
        return try apply(autoTone, to: image, [image, black, white, gamma])
    }
    private static func sample(_ image: CIImage, engine: ImageEngine) -> [[Double]] {
        let preview = engine.resized(image, maxDimension: 96)
        let w = max(1,Int(preview.extent.width)), h = max(1,Int(preview.extent.height))
        var pixels = [UInt8](repeating: 0, count: w*h*4)
        engine.context.render(preview, toBitmap: &pixels, rowBytes: w*4, bounds: CGRect(x:0,y:0,width:w,height:h), format: .RGBA8, colorSpace: engine.colorSpace)
        return stride(from:0,to:pixels.count,by:4).filter { pixels[$0+3] > 127 }.map { [Double(pixels[$0])/255,Double(pixels[$0+1])/255,Double(pixels[$0+2])/255] }
    }
}
