import AppKit
import ImageIO
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift export-emote-atlas.swift source.png output.tga")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot read generated atlas")
}
// Export to a power-of-two, uncompressed 32-bit TGA supported by the game.
let side = 1024
var rgba = [UInt8](repeating: 0, count: side * side * 4)
rgba.withUnsafeMutableBytes { bytes in
    let context = CGContext(data: bytes.baseAddress, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
}
var header = [UInt8](repeating: 0, count: 18)
header[2] = 2
header[12] = UInt8(side & 255)
header[13] = UInt8(side >> 8)
header[14] = header[12]
header[15] = header[13]
header[16] = 32
header[17] = 0x28 // Top-left origin and eight alpha bits.
var bgra = rgba
var transparent = 0
for i in stride(from: 0, to: rgba.count, by: 4) {
    let alpha = Int(rgba[i + 3])
    if alpha == 0 { transparent += 1 }
    // TGA stores straight-alpha BGRA, not premultiplied color.
    for (outChannel, inChannel) in [(0, 2), (1, 1), (2, 0)] {
        bgra[i + outChannel] = alpha == 0 ? 0 : UInt8(min(255, Int(rgba[i + inChannel]) * 255 / alpha))
    }
}
var output = Data(header)
output.append(contentsOf: bgra)
try output.write(to: outputURL)
print("Exported \(side)x\(side) RGBA TGA; \(transparent) fully transparent pixels")
