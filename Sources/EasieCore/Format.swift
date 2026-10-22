import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Every file format Easie understands, as an input, an output, or both.
public enum Format: String, CaseIterable, Identifiable, Sendable {
    case pdf, docx, doc, odt, rtf, html, txt, md, pages
    case pptx, key
    case xlsx, numbers, csv, tsv, json
    case png, jpg, heic, tiff, gif, bmp, webp

    public enum Group: String, CaseIterable, Sendable {
        case documents = "Documents"
        case slides = "Slides"
        case data = "Spreadsheets & Data"
        case images = "Images"
    }

    /// How a source file is read internally.
    enum Kind { case richText, pdf, image, table, presentation, iWork }

    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }
    public var fileExtension: String { rawValue }

    /// A two-word hint shown under the format label.
    public var hint: String {
        switch self {
        case .pdf: "Document"
        case .docx: "Word"
        case .doc: "Word 97"
        case .odt: "OpenDocument"
        case .rtf: "Rich Text"
        case .html: "Web page"
        case .txt: "Plain text"
        case .md: "Markdown"
        case .pages: "Apple Pages"
        case .pptx: "PowerPoint"
        case .key: "Keynote"
        case .xlsx: "Excel"
        case .numbers: "Apple Numbers"
        case .png: "Lossless"
        case .jpg: "Photo"
        case .heic: "Small photo"
        case .tiff: "Print"
        case .gif: "Simple image"
        case .bmp: "Bitmap"
        case .webp: "Web image"
        case .json: "Data"
        case .csv: "Spreadsheet"
        case .tsv: "Tab-separated"
        }
    }

    public var group: Group {
        switch self {
        case .pdf, .docx, .doc, .odt, .rtf, .html, .txt, .md, .pages: .documents
        case .pptx, .key: .slides
        case .xlsx, .numbers, .csv, .tsv, .json: .data
        case .png, .jpg, .heic, .tiff, .gif, .bmp, .webp: .images
        }
    }

    /// The Apple app this format can only be read or written with.
    public var requiredApp: AppleApp? {
        switch self {
        case .pages: .pages
        case .key: .keynote
        case .numbers: .numbers
        default: nil
        }
    }

    var kind: Kind {
        switch self {
        case .pdf: .pdf
        case .docx, .doc, .odt, .rtf, .html, .txt, .md: .richText
        case .png, .jpg, .heic, .tiff, .gif, .bmp, .webp: .image
        case .xlsx, .json, .csv, .tsv: .table
        case .pptx: .presentation
        case .pages, .key, .numbers: .iWork
        }
    }

    public var utType: UTType {
        switch self {
        case .pdf: .pdf
        case .docx: UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        case .doc: UTType("com.microsoft.word.doc") ?? .data
        case .odt: UTType("org.oasis-open.opendocument.text") ?? .data
        case .rtf: .rtf
        case .html: .html
        case .txt: .plainText
        case .md: UTType("net.daringfireball.markdown") ?? .plainText
        case .pages: UTType(filenameExtension: "pages") ?? .data
        case .pptx: UTType("org.openxmlformats.presentationml.presentation") ?? .data
        case .key: UTType(filenameExtension: "key") ?? .data
        case .xlsx: UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
        case .numbers: UTType(filenameExtension: "numbers") ?? .data
        case .png: .png
        case .jpg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        case .webp: .webP
        case .json: .json
        case .csv: .commaSeparatedText
        case .tsv: .tabSeparatedText
        }
    }

    /// Detects a file's format from its extension.
    public init?(fileURL: URL) {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "jpeg", "jpe": self = .jpg
        case "tif": self = .tiff
        case "htm", "xhtml": self = .html
        case "markdown", "mdown", "mkd": self = .md
        case "text", "log": self = .txt
        case "heif": self = .heic
        default:
            guard let format = Format(rawValue: ext) else { return nil }
            self = format
        }
    }

    /// The formats this one can be converted into, most useful first.
    public var targets: [Format] {
        let images: [Format] = [.png, .jpg, .heic, .tiff, .gif, .bmp, .webp]
        let candidates: [Format] = switch self {
        case .docx, .doc, .odt, .rtf, .html, .txt, .md: [.pdf, .docx, .doc, .odt, .rtf, .html, .txt, .md, .pages, .json, .png, .jpg]
        case .pdf: [.docx, .odt, .rtf, .html, .txt, .md, .json, .png, .jpg, .tiff, .heic]
        case .png, .jpg, .heic, .tiff, .gif, .bmp, .webp: images + [.pdf, .txt, .docx, .json]
        case .csv, .tsv, .json: [.xlsx, .csv, .tsv, .json, .numbers, .pdf, .docx, .html, .md, .txt]
        case .xlsx: [.csv, .tsv, .json, .numbers, .pdf, .docx, .html, .md, .txt]
        case .pptx: [.pdf, .key, .png, .jpg, .docx, .txt, .md, .json, .html, .rtf, .odt]
        case .pages: [.pdf, .docx, .doc, .odt, .rtf, .html, .txt, .md, .json, .png, .jpg]
        case .key: [.pdf, .pptx, .png, .jpg, .docx, .txt, .md, .json, .html, .rtf]
        case .numbers: [.xlsx, .csv, .tsv, .json, .pdf, .docx, .html, .md, .txt]
        }
        // Writing Pages, Keynote or Numbers files needs that app. (Reading them is offered
        // regardless, and explains how to get the app if it's missing.)
        return candidates.filter { $0 != self && $0.isWritable && ($0.requiredApp?.isInstalled ?? true) }
    }

    private static let writableImageTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    /// Image encoders depend on the Mac (e.g. HEIC and WebP), so ask ImageIO.
    var isWritable: Bool {
        group != .images || Format.writableImageTypes.contains(utType.identifier)
    }
}
