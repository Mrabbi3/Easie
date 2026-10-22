import EasieCore
import SwiftUI

extension Format {
    /// Each format's familiar colour (Word blue, Excel green, PDF red…).
    var tint: Color {
        switch self {
        case .pdf: Color(red: 0.89, green: 0.18, blue: 0.16)
        case .docx, .doc: Color(red: 0.10, green: 0.35, blue: 0.74)
        case .odt: Color(red: 0.12, green: 0.53, blue: 0.90)
        case .rtf: Color(red: 0.55, green: 0.32, blue: 0.80)
        case .html: Color(red: 0.89, green: 0.30, blue: 0.15)
        case .txt: Color(red: 0.45, green: 0.47, blue: 0.50)
        case .md: Color(red: 0.20, green: 0.22, blue: 0.25)
        case .pages: Color(red: 1.00, green: 0.58, blue: 0.00)
        case .pptx: Color(red: 0.82, green: 0.28, blue: 0.15)
        case .key: Color(red: 0.04, green: 0.52, blue: 1.00)
        case .xlsx: Color(red: 0.11, green: 0.44, blue: 0.26)
        case .numbers: Color(red: 0.20, green: 0.70, blue: 0.30)
        case .csv: Color(red: 0.18, green: 0.55, blue: 0.34)
        case .tsv: Color(red: 0.10, green: 0.55, blue: 0.55)
        case .json: Color(red: 0.56, green: 0.27, blue: 0.68)
        case .png: Color(red: 0.00, green: 0.62, blue: 0.62)
        case .jpg: Color(red: 0.93, green: 0.60, blue: 0.00)
        case .heic: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .tiff: Color(red: 0.40, green: 0.45, blue: 0.55)
        case .gif: Color(red: 1.00, green: 0.18, blue: 0.33)
        case .bmp: Color(red: 0.64, green: 0.52, blue: 0.37)
        case .webp: Color(red: 0.20, green: 0.67, blue: 0.86)
        }
    }

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .html: "globe"
        case .md: "number"
        case .txt: "text.alignleft"
        case .pages: "pencil.line"
        case .pptx, .key: "play.rectangle"
        case .xlsx, .numbers, .csv, .tsv: "tablecells"
        case .json: "curlybraces"
        case .png, .jpg, .heic, .tiff, .gif, .bmp, .webp: "photo"
        case .docx, .doc, .odt, .rtf: "doc.text"
        }
    }
}

/// A page with a folded top-right corner.
struct PageShape: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.3
        let r = rect.width * 0.1
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The dog-ear of `PageShape`.
struct FoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.3
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold * 0.8))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - fold * 0.8, y: rect.minY + fold),
                          control: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.closeSubpath()
        return path
    }
}

/// A file icon in the classic style: white page, coloured symbol, and a label band.
struct FormatGlyph: View {
    let format: Format

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                PageShape()
                    .fill(Color.white)
                    .overlay(PageShape().stroke(Color.black.opacity(0.12), lineWidth: 0.75))
                FoldShape()
                    .fill(LinearGradient(colors: [Color(white: 0.84), Color(white: 0.95)], startPoint: .bottomLeading, endPoint: .topTrailing))
                Image(systemName: format.symbol)
                    .font(.system(size: size.width * 0.34, weight: .semibold))
                    .foregroundStyle(format.tint)
                    .frame(width: size.width, height: size.height * 0.58)
                    .padding(.top, size.height * 0.06)
                Text(format.label)
                    .font(.system(size: size.width * 0.24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 3)
                    .frame(width: size.width * 0.92, height: size.height * 0.27)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(LinearGradient(colors: [format.tint.opacity(0.85), format.tint], startPoint: .top, endPoint: .bottom))
                    )
                    .offset(x: -size.width * 0.08, y: size.height * 0.63)
            }
        }
        .drawingGroup()  // one flattened layer per icon keeps the pop animation smooth
        .accessibilityHidden(true)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1.5)
    }
}
