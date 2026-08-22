import CoreText
import UIKit

/// 요약 → A4 PDF (#4 공유하기)
/// SummaryTextBuilder와 같은 입력을 받아 서식만 다르게 그린다.
enum SummaryPDFRenderer {
    /// A4 72dpi
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 56

    static func pdfData(title: String,
                        metaText: String,
                        oneLiner: String,
                        sections: [SummarySection],
                        todos: [SummaryTextBuilder.TodoLine]) -> Data {
        render(attributedString(title: title,
                                metaText: metaText,
                                oneLiner: oneLiner,
                                sections: sections,
                                todos: todos))
    }

    // MARK: - 서식

    static func attributedString(title: String,
                                 metaText: String,
                                 oneLiner: String,
                                 sections: [SummarySection],
                                 todos: [SummaryTextBuilder.TodoLine]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        output.append(paragraph(title, font: .systemFont(ofSize: 24, weight: .bold),
                                spacingAfter: 4))
        output.append(paragraph(metaText, font: .systemFont(ofSize: 11),
                                color: .secondaryLabel, spacingAfter: 20))

        if !oneLiner.isEmpty {
            output.append(heading("한 줄 요약"))
            output.append(body(oneLiner))
        }
        for section in sections where !section.bullets.isEmpty {
            output.append(heading(section.title))
            for bullet in section.bullets {
                output.append(bulletBody("•", bullet))
            }
        }
        if !todos.isEmpty {
            output.append(heading("할 일"))
            for todo in todos {
                output.append(bulletBody(todo.isDone ? "☑" : "☐",
                                         SummaryTextBuilder.todoText(todo)))
            }
        }
        return output
    }

    private static func heading(_ text: String) -> NSAttributedString {
        paragraph(text, font: .systemFont(ofSize: 15, weight: .semibold),
                  spacingBefore: 16, spacingAfter: 6)
    }

    private static func body(_ text: String) -> NSAttributedString {
        paragraph(text, font: .systemFont(ofSize: 12), spacingAfter: 4)
    }

    /// 두 번째 줄부터 글머리표 너비만큼 들여쓴다
    private static func bulletBody(_ marker: String, _ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 3
        style.headIndent = 14
        return NSAttributedString(string: "\(marker) \(text)\n", attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
        ])
    }

    private static func paragraph(_ text: String,
                                  font: UIFont,
                                  color: UIColor = .label,
                                  spacingBefore: CGFloat = 0,
                                  spacingAfter: CGFloat = 0) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return NSAttributedString(string: text + "\n", attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    // MARK: - 페이지 나누기

    /// CoreText로 한 페이지씩 채우고, 남은 글자가 있으면 다음 페이지를 연다.
    static func render(_ attributed: NSAttributedString) -> Data {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = CGRect(x: margin, y: margin,
                              width: pageSize.width - margin * 2,
                              height: pageSize.height - margin * 2)
        // CoreText는 y가 위로 자라는 좌표계라 PDF 좌표계로 뒤집어 그린다
        let path = CGPath(rect: CGRect(x: textRect.minX,
                                       y: pageSize.height - textRect.maxY,
                                       width: textRect.width,
                                       height: textRect.height), transform: nil)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return renderer.pdfData { context in
            var start = 0
            repeat {
                context.beginPage()
                let cgContext = context.cgContext
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageSize.height)
                cgContext.scaleBy(x: 1, y: -1)

                let frame = CTFramesetterCreateFrame(
                    framesetter, CFRange(location: start, length: 0), path, nil)
                CTFrameDraw(frame, cgContext)

                // 한 글자도 못 앉히면(빈 문서·너무 좁은 여백) 무한 루프가 되므로 끊는다
                let drawn = CTFrameGetVisibleStringRange(frame).length
                guard drawn > 0 else { break }
                start += drawn
            } while start < attributed.length
        }
    }
}
