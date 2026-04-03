#!/usr/bin/env swift

import AppKit
import Foundation
import Vision

func usage() -> Never {
    fputs("usage: ocr_text.swift <image-path> [regex]\n", stderr)
    exit(64)
}

guard CommandLine.arguments.count >= 2 else {
    usage()
}

let imagePath = CommandLine.arguments[1]
let regexPattern = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : nil

guard let image = NSImage(contentsOfFile: imagePath) else {
    fputs("failed to read image: \(imagePath)\n", stderr)
    exit(66)
}

var proposedRect = NSRect(origin: .zero, size: image.size)
guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fputs("failed to create cgImage for: \(imagePath)\n", stderr)
    exit(66)
}

let request = VNRecognizeTextRequest()
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

do {
    try handler.perform([request])
} catch {
    fputs("vision OCR failed: \(error)\n", stderr)
    exit(1)
}

let width = CGFloat(cgImage.width)
let height = CGFloat(cgImage.height)
let regex = regexPattern.flatMap { try? NSRegularExpression(pattern: $0) }

func matches(_ text: String) -> Bool {
    guard let regex else {
        return true
    }
    let range = NSRange(location: 0, length: text.utf16.count)
    return regex.firstMatch(in: text, options: [], range: range) != nil
}

let observations = (request.results ?? []).sorted {
    let y0 = (1 - $0.boundingBox.origin.y - $0.boundingBox.size.height) * height
    let y1 = (1 - $1.boundingBox.origin.y - $1.boundingBox.size.height) * height
    if y0 == y1 {
        return $0.boundingBox.origin.x < $1.boundingBox.origin.x
    }
    return y0 < y1
}

for observation in observations {
    guard let candidate = observation.topCandidates(1).first else {
        continue
    }

    let text = candidate.string
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty, matches(text) else {
        continue
    }

    let box = observation.boundingBox
    let left = Int(box.origin.x * width)
    let top = Int((1 - box.origin.y - box.size.height) * height)
    let boxWidth = Int(box.size.width * width)
    let boxHeight = Int(box.size.height * height)

    print("\(text)\t\(left)\t\(top)\t\(boxWidth)\t\(boxHeight)")
}
