#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Options {
    var baseline = "Tests/ScreenshotBaselines/iPhone_17_Pro/light"
    var actual = "BuildArtifacts/screenshots/actual/iPhone_17_Pro/light"
    var diff = "BuildArtifacts/screenshots/diff/iPhone_17_Pro/light"
    var pixelThreshold = 1.0
    var maxDifferentPixels = 250
    var maxDifferentRatio = 0.00025
    var maxMeanChannelDelta = 0.35
}

struct ImageBuffer {
    let width: Int
    let height: Int
    var pixels: [UInt8]
}

struct Comparison {
    let differentPixels: Int
    let allowedDifferentPixels: Int
    let meanChannelDelta: Double
}

enum FailureKind: String {
    case missingActual = "missing actual"
    case sizeMismatch = "size mismatch"
    case unexpectedActual = "unexpected screenshot"
    case pixelDiff = "pixel-diff"
}

enum CompareError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case missingDirectory(String)
    case missingImage(String)
    case unreadableImage(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidArguments(let message), .missingDirectory(let message), .missingImage(let message),
             .unreadableImage(let message), .writeFailed(let message):
            return message
        }
    }
}

func parseOptions() throws -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let flag = arguments.removeFirst()
        guard !["--help", "-h"].contains(flag) else {
            print("""
            Usage: compare-screenshots.swift [options]
              --baseline <dir>              Baseline PNG directory
              --actual <dir>                Actual PNG directory
              --diff <dir>                  Diff PNG output directory
              --pixel-threshold <number>    Channel delta that marks a pixel changed
              --max-different-pixels <int>  Absolute changed-pixel limit
              --max-different-ratio <num>   Ratio changed-pixel limit
              --max-mean-channel-delta <n>  Mean RGB channel delta limit
            """)
            exit(0)
        }
        guard !arguments.isEmpty else {
            throw CompareError.invalidArguments("Missing value for \(flag)")
        }
        let value = arguments.removeFirst()
        switch flag {
        case "--baseline":
            options.baseline = value
        case "--actual":
            options.actual = value
        case "--diff":
            options.diff = value
        case "--pixel-threshold":
            options.pixelThreshold = try double(value, flag: flag)
        case "--max-different-pixels":
            options.maxDifferentPixels = try int(value, flag: flag)
        case "--max-different-ratio":
            options.maxDifferentRatio = try double(value, flag: flag)
        case "--max-mean-channel-delta":
            options.maxMeanChannelDelta = try double(value, flag: flag)
        default:
            throw CompareError.invalidArguments("Unknown argument: \(flag)")
        }
    }
    return options
}

func int(_ value: String, flag: String) throws -> Int {
    guard let parsed = Int(value) else {
        throw CompareError.invalidArguments("Invalid integer for \(flag): \(value)")
    }
    return parsed
}

func double(_ value: String, flag: String) throws -> Double {
    guard let parsed = Double(value) else {
        throw CompareError.invalidArguments("Invalid number for \(flag): \(value)")
    }
    return parsed
}

func pngFiles(in directory: String) throws -> [URL] {
    let url = URL(fileURLWithPath: directory)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw CompareError.missingDirectory("Directory not found: \(directory)")
    }
    let files = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil
    )
    return files.filter { $0.pathExtension.lowercased() == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func loadImage(_ url: URL) throws -> ImageBuffer {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CompareError.unreadableImage("Unable to read image: \(url.path)")
    }
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return ImageBuffer(width: width, height: height, pixels: pixels)
}

func compare(baseline: ImageBuffer, actual: ImageBuffer, options: Options) -> Comparison {
    let pixelCount = baseline.width * baseline.height
    let allowed = min(options.maxDifferentPixels, Int((Double(pixelCount) * options.maxDifferentRatio).rounded(.down)))
    var differentPixels = 0
    var channelDeltaSum = 0.0
    for index in stride(from: 0, to: baseline.pixels.count, by: 4) {
        let red = abs(Int(baseline.pixels[index]) - Int(actual.pixels[index]))
        let green = abs(Int(baseline.pixels[index + 1]) - Int(actual.pixels[index + 1]))
        let blue = abs(Int(baseline.pixels[index + 2]) - Int(actual.pixels[index + 2]))
        let channelDelta = Double(red + green + blue) / 3.0
        channelDeltaSum += channelDelta
        if channelDelta > options.pixelThreshold {
            differentPixels += 1
        }
    }
    return Comparison(
        differentPixels: differentPixels,
        allowedDifferentPixels: allowed,
        meanChannelDelta: channelDeltaSum / Double(pixelCount)
    )
}

func writeDiff(name: String, baseline: ImageBuffer, actual: ImageBuffer, options: Options) throws -> String {
    try FileManager.default.createDirectory(atPath: options.diff, withIntermediateDirectories: true)
    let pixelCount = baseline.width * baseline.height
    var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
    for pixel in 0..<pixelCount {
        let index = pixel * 4
        let red = abs(Int(baseline.pixels[index]) - Int(actual.pixels[index]))
        let green = abs(Int(baseline.pixels[index + 1]) - Int(actual.pixels[index + 1]))
        let blue = abs(Int(baseline.pixels[index + 2]) - Int(actual.pixels[index + 2]))
        let channelDelta = Double(red + green + blue) / 3.0
        if channelDelta > options.pixelThreshold {
            pixels[index] = 255
            pixels[index + 1] = 0
            pixels[index + 2] = 0
            pixels[index + 3] = 255
        } else {
            let gray = UInt8(Double(Int(baseline.pixels[index]) + Int(baseline.pixels[index + 1]) + Int(baseline.pixels[index + 2])) / 9.0)
            pixels[index] = gray
            pixels[index + 1] = gray
            pixels[index + 2] = gray
            pixels[index + 3] = 255
        }
    }
    let path = URL(fileURLWithPath: options.diff).appendingPathComponent(name.replacingOccurrences(of: ".png", with: ".diff.png"))
    guard let context = CGContext(
        data: &pixels,
        width: baseline.width,
        height: baseline.height,
        bitsPerComponent: 8,
        bytesPerRow: baseline.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CompareError.writeFailed("Unable to create diff image: \(path.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CompareError.writeFailed("Unable to write diff image: \(path.path)")
    }
    return path.path
}

do {
    let options = try parseOptions()
    if FileManager.default.fileExists(atPath: options.diff) {
        try FileManager.default.removeItem(atPath: options.diff)
    }
    let baselines = try pngFiles(in: options.baseline)
    if baselines.isEmpty {
        throw CompareError.missingImage("No baseline PNG files found in \(options.baseline)")
    }

    var failures: [String] = []
    for baselineURL in baselines {
        let name = baselineURL.lastPathComponent
        let actualURL = URL(fileURLWithPath: options.actual).appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: actualURL.path) else {
            failures.append("""
            FAIL \(name) [\(FailureKind.missingActual.rawValue)]
              baseline: \(baselineURL.path)
              actual:   \(actualURL.path)
            """)
            continue
        }
        let baseline = try loadImage(baselineURL)
        let actual = try loadImage(actualURL)
        guard baseline.width == actual.width, baseline.height == actual.height else {
            failures.append("""
            FAIL \(name) [\(FailureKind.sizeMismatch.rawValue)]
              baseline: \(baselineURL.path)
              actual:   \(actualURL.path)
              baseline size: \(baseline.width)x\(baseline.height)
              actual size:   \(actual.width)x\(actual.height)
            """)
            continue
        }
        let result = compare(baseline: baseline, actual: actual, options: options)
        if result.differentPixels > result.allowedDifferentPixels || result.meanChannelDelta > options.maxMeanChannelDelta {
            let diffPath = try writeDiff(name: name, baseline: baseline, actual: actual, options: options)
            failures.append("""
            FAIL \(name) [\(FailureKind.pixelDiff.rawValue)]
              baseline: \(baselineURL.path)
              actual:   \(actualURL.path)
              diff:     \(diffPath)
              size:     \(baseline.width)x\(baseline.height)
              changed:  \(result.differentPixels) px
              allowed:  \(result.allowedDifferentPixels) px
              mean channel delta: \(String(format: "%.4f", result.meanChannelDelta))
            """)
        } else {
            print("PASS \(name) changed=\(result.differentPixels)/\(result.allowedDifferentPixels) mean=\(String(format: "%.4f", result.meanChannelDelta))")
        }
    }

    let actualNames = Set((try? pngFiles(in: options.actual).map(\.lastPathComponent)) ?? [])
    let baselineNames = Set(baselines.map(\.lastPathComponent))
    for extra in actualNames.subtracting(baselineNames).sorted() {
        let actualURL = URL(fileURLWithPath: options.actual).appendingPathComponent(extra)
        let expectedBaselineURL = URL(fileURLWithPath: options.baseline).appendingPathComponent(extra)
        failures.append("""
        FAIL \(extra) [\(FailureKind.unexpectedActual.rawValue)]
          baseline: \(expectedBaselineURL.path)
          actual:   \(actualURL.path)
        """)
    }

    if !failures.isEmpty {
        print(failures.joined(separator: "\n"))
        print("""

        Screenshot comparison failed. Inspect actual PNGs under \(options.actual) and diff PNGs under \(options.diff).
        To accept intentional visual changes, run Scripts/screenshots/run-screenshot-tests.sh update and commit the updated baselines under \(options.baseline).
        """)
        exit(1)
    }
} catch {
    print("ERROR \(error)", to: &standardError)
    exit(2)
}

var standardError = StandardError()

struct StandardError: TextOutputStream {
    mutating func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
