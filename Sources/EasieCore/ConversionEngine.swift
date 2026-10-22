import AppKit
import PDFKit
import Vision

public enum ConversionError: LocalizedError {
    case unsupportedSource(String)
    case unsupportedTarget(Format, Format)
    case unreadable(String)
    case notTabular
    case noText
    case empty
    case writeFailed(String)
    case needsApp(String)
    case automationDenied(String)
    case appFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource(let ext): "Easie can't read .\(ext) files yet."
        case .unsupportedTarget(let from, let to): "\(from.label) files can't be turned into \(to.label)."
        case .unreadable(let name): "Couldn't open \(name). It may be damaged or password-protected."
        case .notTabular: "This data isn't shaped like a table (a list of rows or records)."
        case .noText: "No readable text was found in this file."
        case .empty: "The file looks empty."
        case .writeFailed(let name): "Couldn't save \(name)."
        case .needsApp(let app): "This needs Apple \(app), which is free on the Mac App Store."
        case .automationDenied(let app): "Easie needs permission to use \(app). Turn it on in System Settings → Privacy & Security → Automation."
        case .appFailed(let app, let reason): "\(app) couldn't convert this file: \(reason)"
        }
    }
}

/// What a file holds once it's loaded. Every converter goes through one of these.
enum Content {
    case rich(NSAttributedString)
    case pdf(PDFDocument)
    case images([CGImage])
    case sheets([Sheet])
    case slides([Slide])
    case json(JSONValue)
}

/// Converts files between formats using only what ships with macOS:
/// the AppKit text system, PDFKit, ImageIO and Vision. Nothing leaves the Mac.
public enum ConversionEngine {
    /// Converts `input` to `target` and returns the files written.
    /// Output goes next to the original unless `outputDirectory` is given, and never overwrites anything.
    @discardableResult
    public static func convert(_ input: URL, to target: Format, outputDirectory: URL? = nil) throws -> [URL] {
        guard let source = Format(fileURL: input) else { throw ConversionError.unsupportedSource(input.pathExtension) }
        guard source.targets.contains(target) else { throw ConversionError.unsupportedTarget(source, target) }
        if let outputDirectory {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        let namer = OutputNamer(
            directory: outputDirectory ?? input.deletingLastPathComponent(),
            baseName: input.deletingPathExtension().lastPathComponent,
            format: target,
            pieceName: source.group == .slides ? "slide" : "page"
        )
        if let plan = AppPlan.plan(from: source, to: target) {
            return try convert(input, using: plan, to: target, namer: namer)
        }
        return try write(try load(input, as: source), as: target, using: namer)
    }

    /// Conversions that go through Pages, Keynote or Numbers.
    private static func convert(_ input: URL, using plan: AppPlan, to target: Format, namer: OutputNamer) throws -> [URL] {
        guard plan.app.isInstalled else { throw ConversionError.needsApp(plan.app.rawValue) }
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("Easie-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        var appInput = input
        if let step = plan.prepare {
            guard let prepared = try convert(input, to: step, outputDirectory: workspace).first else { throw ConversionError.empty }
            appInput = prepared
        }
        if plan.produces == target {
            let output = namer.nextURL()
            try AppleAppBridge.convert(appInput, with: plan.app, to: output, as: target)
            return [output]
        }
        let intermediate = workspace.appendingPathComponent(namer.baseName + "." + plan.produces.fileExtension)
        try AppleAppBridge.convert(appInput, with: plan.app, to: intermediate, as: plan.produces)
        return try write(try load(intermediate, as: plan.produces), as: target, using: namer)
    }

    // MARK: Reading

    static func load(_ url: URL, as format: Format) throws -> Content {
        let name = url.lastPathComponent
        switch format {
        case .pdf:
            guard let document = PDFDocument(url: url), !document.isLocked else { throw ConversionError.unreadable(name) }
            return .pdf(document)
        case .txt:
            return .rich(plain(try readText(url)))
        case .md:
            return .rich(try attributed(html: Markdown.html(from: try readText(url))))
        case .html:
            return .rich(try attributed(html: SafeHTML.sanitize(try readText(url)), baseURL: url.deletingLastPathComponent()))
        case .docx, .doc, .odt, .rtf:
            do {
                return .rich(try NSAttributedString(url: url, options: [.documentType: documentType(for: format)], documentAttributes: nil))
            } catch {
                throw ConversionError.unreadable(name)
            }
        case .png, .jpg, .heic, .tiff, .gif, .bmp, .webp:
            let images = loadImages(url, allFrames: format == .tiff)
            guard !images.isEmpty else { throw ConversionError.unreadable(name) }
            return .images(images)
        case .csv, .tsv:
            let rows = Tables.parse(try readText(url), separator: format == .csv ? "," : "\t")
            return .sheets([Sheet(name: url.deletingPathExtension().lastPathComponent, rows: rows)])
        case .xlsx:
            do { return .sheets(try XLSX.read(url)) } catch { throw ConversionError.unreadable(name) }
        case .pptx:
            do { return .slides(try PPTX.read(url)) } catch { throw ConversionError.unreadable(name) }
        case .pages, .key, .numbers:
            throw ConversionError.needsApp(format.requiredApp!.rawValue)
        case .json:
            do { return .json(try JSONParser.parse(try Data(contentsOf: url))) } catch { throw ConversionError.unreadable(name) }
        }
    }

    private static func readText(_ url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .isoLatin1) { return text }
        throw ConversionError.unreadable(url.lastPathComponent)
    }

    /// Loads image frames upright (honouring EXIF orientation).
    private static func loadImages(_ url: URL, allFrames: Bool) -> [CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let indices = allFrames ? Array(0..<CGImageSourceGetCount(source)) : [CGImageSourceGetPrimaryImageIndex(source)]
        return indices.compactMap { index in
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            // Decoding is capped so a hostile "decompression bomb" image can't eat all memory.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(max(width, height, 1), 16_384),
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        }
    }

    // MARK: Writing

    static func write(_ content: Content, as target: Format, using namer: OutputNamer) throws -> [URL] {
        switch target {
        case .pdf:
            return [try namer.save(try pdfData(content))]
        case .docx, .doc, .odt, .rtf:
            let text = try richText(content)
            let data = try text.data(from: NSRange(location: 0, length: text.length),
                                     documentAttributes: [.documentType: documentType(for: target)])
            return [try namer.save(data)]
        case .html:
            switch content {
            case .sheets(let sheets): return [try namer.save(Data(Tables.html(sheets).utf8))]
            case .slides(let slides): return [try namer.save(Data(Slides.html(slides).utf8))]
            default: break
            }
            let text = try richText(content)
            let data = try text.data(from: NSRange(location: 0, length: text.length),
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
            return [try namer.save(data)]
        case .txt:
            return [try namer.save(Data(try plainText(content).utf8))]
        case .md:
            let markdown: String = switch content {
            case .sheets(let sheets): Tables.markdown(sheets)
            case .slides(let slides): Slides.markdown(slides)
            case .json(let value): "```json\n" + value.serialized() + "\n```\n"
            default: Markdown.markdown(from: try richText(content))
            }
            return [try namer.save(Data(markdown.utf8))]
        case .json:
            return [try namer.save(Data((try json(content).serialized() + "\n").utf8))]
        case .csv, .tsv:
            // One file per sheet: "Budget - January.csv", "Budget - February.csv"…
            let sheets = try table(content)
            return try sheets.map { sheet in
                let text = Tables.delimited(sheet.rows, separator: target == .csv ? "," : "\t")
                return try namer.save(Data(text.utf8), suffix: sheets.count > 1 ? " - " + sheet.name : "")
            }
        case .xlsx:
            return [try namer.save(XLSX.write(try table(content)))]
        case .pptx, .pages, .key, .numbers:
            throw ConversionError.needsApp(target.requiredApp?.rawValue ?? "Keynote")
        case .png, .jpg, .heic, .tiff, .gif, .bmp, .webp:
            let pictures = try images(content)
            guard !pictures.isEmpty else { throw ConversionError.empty }
            if pictures.count == 1 {
                return [try namer.save { try writeImage(pictures[0], to: $0, as: target) }]
            }
            return try pictures.enumerated().map { index, picture in
                try namer.save(suffix: " \(namer.pieceName) \(index + 1)") { try writeImage(picture, to: $0, as: target) }
            }
        }
    }

    static func documentType(for format: Format) -> NSAttributedString.DocumentType {
        switch format {
        case .docx: .officeOpenXML
        case .doc: .docFormat
        case .odt: .openDocument
        case .html: .html
        case .txt, .md: .plain
        default: .rtf
        }
    }

    // MARK: Bridges between kinds of content

    static func richText(_ content: Content) throws -> NSAttributedString {
        switch content {
        case .rich(let text):
            return text
        case .pdf(let document):
            let out = NSMutableAttributedString()
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.attributedString else { continue }
                if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
                out.append(page)
            }
            if out.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return plain(try recognizeText(in: renderPages(document)))  // a scanned PDF
            }
            return out
        case .images(let pictures):
            return plain(try recognizeText(in: pictures))
        case .sheets(let sheets):
            return try attributed(html: Tables.html(sheets))
        case .slides(let slides):
            return try attributed(html: Slides.html(slides))
        case .json(let value):
            return plain(value.serialized(), monospaced: true)
        }
    }

    static func plainText(_ content: Content) throws -> String {
        switch content {
        case .rich(let text): return text.string
        case .pdf: return try richText(content).string
        case .images(let pictures): return try recognizeText(in: pictures)
        case .sheets(let sheets): return Tables.aligned(sheets)
        case .slides(let slides): return Slides.text(slides)
        case .json(let value): return value.serialized() + "\n"
        }
    }

    static func table(_ content: Content) throws -> [Sheet] {
        switch content {
        case .sheets(let sheets): return sheets
        case .json(let value):
            guard let rows = Tables.table(from: value) else { throw ConversionError.notTabular }
            return [Sheet(name: "Sheet1", rows: rows)]
        default: throw ConversionError.notTabular
        }
    }

    static func json(_ content: Content) throws -> JSONValue {
        switch content {
        case .json(let value):
            return value
        case .sheets(let sheets):
            if sheets.count == 1 { return Tables.records(sheets[0].rows) }
            return .object(sheets.map { ($0.name, Tables.records($0.rows)) })
        case .slides(let slides):
            return Slides.json(slides)
        case .rich(let text):
            let paragraphs = text.string.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return .object([
                ("title", .string(paragraphs.first ?? "")),
                ("wordCount", .number(String(text.string.split(whereSeparator: \.isWhitespace).count))),
                ("paragraphs", .array(paragraphs.map { .string($0) })),
            ])
        case .pdf(let document):
            let attributes = document.documentAttributes ?? [:]
            var pages: [JSONValue] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                var text = page.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let image = renderPage(page) {
                    text = (try? recognizeText(in: [image])) ?? ""
                }
                pages.append(.object([("page", .number(String(index + 1))), ("text", .string(text))]))
            }
            return .object([
                ("title", .string(attributes[PDFDocumentAttribute.titleAttribute] as? String ?? "")),
                ("author", .string(attributes[PDFDocumentAttribute.authorAttribute] as? String ?? "")),
                ("pageCount", .number(String(document.pageCount))),
                ("pages", .array(pages)),
            ])
        case .images(let pictures):
            let described: [JSONValue] = pictures.map { picture in
                let lines = recognizeLines(in: picture)
                return .object([
                    ("width", .number(String(picture.width))),
                    ("height", .number(String(picture.height))),
                    ("text", .string(lines.joined(separator: "\n"))),
                    ("lines", .array(lines.map { .string($0) })),
                ])
            }
            return described.count == 1 ? described[0] : .array(described)
        }
    }

    static func pdfData(_ content: Content) throws -> Data {
        switch content {
        case .pdf(let document):
            guard let data = document.dataRepresentation() else { throw ConversionError.empty }
            return data
        case .images(let pictures):
            return pdf(from: pictures)
        default:
            return layoutPDF(try richText(content))
        }
    }

    static func images(_ content: Content) throws -> [CGImage] {
        switch content {
        case .images(let pictures): return pictures
        case .pdf(let document): return renderPages(document)
        default:
            guard let document = PDFDocument(data: try pdfData(content)) else { throw ConversionError.empty }
            return renderPages(document)
        }
    }

    // MARK: Rich text helpers

    static func plain(_ string: String, monospaced: Bool = false) -> NSAttributedString {
        let font = monospaced ? NSFont(name: "Menlo", size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .regular)
                              : NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    /// HTML import uses WebKit, which must run on the main thread. Only HTML Easie wrote itself,
    /// or that went through `SafeHTML`, comes here, so nothing is fetched from the network.
    static func attributed(html: String, baseURL: URL? = nil) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let baseURL { options[NSAttributedString.DocumentReadingOptionKey("BaseURL")] = baseURL }
        return try onMain {
            try NSAttributedString(data: Data(html.utf8), options: options, documentAttributes: nil)
        }
    }

    static func onMain<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    // MARK: PDF rendering

    static var pageSize: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    /// Lays text out across as many pages as it needs, keeping fonts, colours, tables and images.
    /// Runs on the conversion thread (the text system is safe there as long as nothing is shared),
    /// so the popup's spinner keeps moving.
    static func layoutPDF(_ text: NSAttributedString) -> Data {
        do {
            let page = pageSize
            let margin: CGFloat = 54
            let storage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)

            var pageRanges: [NSRange] = []
            while pageRanges.count < 10_000 {
                let container = NSTextContainer(size: CGSize(width: page.width - margin * 2, height: page.height - margin * 2))
                layout.addTextContainer(container)
                let range = layout.glyphRange(for: container)
                if range.length == 0, !pageRanges.isEmpty { break }
                pageRanges.append(range)
                if NSMaxRange(range) >= layout.numberOfGlyphs { break }
            }

            let data = NSMutableData()
            var box = CGRect(origin: .zero, size: page)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
            for range in pageRanges {
                context.beginPDFPage(nil)
                context.translateBy(x: 0, y: page.height)
                context.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                let origin = CGPoint(x: margin, y: margin)
                if range.length > 0 {
                    layout.drawBackground(forGlyphRange: range, at: origin)
                    layout.drawGlyphs(forGlyphRange: range, at: origin)
                }
                NSGraphicsContext.restoreGraphicsState()
                context.endPDFPage()
            }
            context.closePDF()
            return data as Data
        }
    }

    static func pdf(from pictures: [CGImage]) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return Data() }
        for picture in pictures {
            let longest = CGFloat(max(picture.width, picture.height))
            let scale = min(1, 1200 / longest)
            var box = CGRect(x: 0, y: 0, width: CGFloat(picture.width) * scale, height: CGFloat(picture.height) * scale)
            context.beginPage(mediaBox: &box)
            context.draw(picture, in: box)
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    static func renderPages(_ document: PDFDocument) -> [CGImage] {
        (0..<document.pageCount).compactMap { document.page(at: $0).flatMap { renderPage($0) } }
    }

    /// Renders a page at 144 dpi on white, respecting its rotation.
    static func renderPage(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        guard let ref = page.pageRef else { return nil }
        let box = ref.getBoxRect(.mediaBox)
        let turned = ref.rotationAngle % 180 != 0
        let size = turned ? CGSize(width: box.height, height: box.width) : box.size
        let scale = min(scale, 3000 / max(size.width, size.height, 1))
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(ref.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        return context.makeImage()
    }

    // MARK: Images

    static func writeImage(_ picture: CGImage, to url: URL, as format: Format) throws {
        let flatten = format == .jpg || format == .bmp
        let image = flatten ? flattened(picture) : picture
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ConversionError.writeFailed(url.lastPathComponent)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.writeFailed(url.lastPathComponent) }
    }

    /// Puts transparent images on white, for formats without transparency.
    private static func flattened(_ picture: CGImage) -> CGImage {
        guard ![.none, .noneSkipFirst, .noneSkipLast].contains(picture.alphaInfo),
              let context = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return picture }
        let rect = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(picture, in: rect)
        return context.makeImage() ?? picture
    }

    // MARK: Text recognition (OCR)

    static func recognizeText(in pictures: [CGImage]) throws -> String {
        let text = pictures.map { recognizeLines(in: $0).joined(separator: "\n") }.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversionError.noText }
        return text
    }

    static func recognizeLines(in picture: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: picture).perform([request])

        // Rebuild reading order: pieces sharing a baseline become one line, read left to right.
        let pieces = (request.results ?? []).compactMap { observation -> (box: CGRect, text: String)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (observation.boundingBox, text)
        }.sorted { $0.box.midY > $1.box.midY }
        var lines: [[(box: CGRect, text: String)]] = []
        for piece in pieces {
            if let last = lines.last?.first, abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) / 2 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }
}

/// Picks output names like "Report.pdf", then "Report (1).pdf", so nothing is ever overwritten.
struct OutputNamer {
    let directory: URL
    let baseName: String
    let format: Format
    /// What one image of a multi-page result is called: "page" or "slide".
    var pieceName = "page"

    func nextURL(suffix: String = "") -> URL {
        var attempt = 0
        while true {
            let counter = attempt == 0 ? "" : " (\(attempt))"
            let url = directory.appendingPathComponent(baseName + suffix + counter + "." + format.fileExtension)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            attempt += 1
        }
    }

    func save(_ data: Data, suffix: String = "") throws -> URL {
        try save(suffix: suffix) { url in
            do { try data.write(to: url, options: .atomic) } catch { throw ConversionError.writeFailed(url.lastPathComponent) }
        }
    }

    func save(suffix: String = "", _ writer: (URL) throws -> Void) throws -> URL {
        let url = nextURL(suffix: suffix)
        try writer(url)
        return url
    }
}
