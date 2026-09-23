import Foundation

struct IconRepresentation {
    let type: String
    let path: String
}

func bigEndianUInt32(_ value: Int) -> Data {
    var value = UInt32(value).bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate_app_icon <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let iconsetDirectory = arguments[1]
let outputPath = arguments[2]
let representations = [
    IconRepresentation(type: "icp4", path: "icon_16x16.png"),
    IconRepresentation(type: "ic11", path: "icon_16x16@2x.png"),
    IconRepresentation(type: "icp5", path: "icon_32x32.png"),
    IconRepresentation(type: "ic12", path: "icon_32x32@2x.png"),
    IconRepresentation(type: "ic07", path: "icon_128x128.png"),
    IconRepresentation(type: "ic13", path: "icon_128x128@2x.png"),
    IconRepresentation(type: "ic08", path: "icon_256x256.png"),
    IconRepresentation(type: "ic14", path: "icon_256x256@2x.png"),
    IconRepresentation(type: "ic09", path: "icon_512x512.png"),
    IconRepresentation(type: "ic10", path: "icon_512x512@2x.png")
]

var body = Data()
for representation in representations {
    let url = URL(fileURLWithPath: iconsetDirectory).appendingPathComponent(representation.path)
    let png = try Data(contentsOf: url)
    body.append(Data(representation.type.utf8))
    body.append(bigEndianUInt32(png.count + 8))
    body.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianUInt32(body.count + 8))
icns.append(body)
try icns.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
