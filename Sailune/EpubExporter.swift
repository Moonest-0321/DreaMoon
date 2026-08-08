import Foundation
import AppKit
import SwiftData

// MARK: - EPUB 匯出器（自含：組裝 + stored-only zip + 直存）
// 設計：epub 規範只要求 mimetype 必須 stored 且為第一個 entry；其餘 entry 允許 stored。
//       故全部用 stored（不壓縮），無需壓縮演算法，zip 正確性完全可控，零外部依賴。
enum EpubExporter {

    // MARK: 對外：一鍵匯出整本書為 EPUB
    @MainActor
    static func exportBook(book: Book) {
        let epubData = buildEpub(book: book)
        writeData(epubData, fileName: sanitize(book.title) + ".epub")
    }

    // MARK: - 組裝 EPUB（回傳 zip 的 Data）
    private static func buildEpub(book: Book) -> Data {
        let sortedVolumes = book.volumes.sorted { $0.sortOrder < $1.sortOrder }

        // 建立 volume / section 的 flat 清單（id / 檔名 / 標題 / xhtml 內容）
        struct VolEntry { let id: String; let file: String; let title: String; let xhtml: String; let sections: [SecEntry] }
        struct SecEntry { let id: String; let file: String; let title: String; let xhtml: String }

        var volumes: [VolEntry] = []
        for (vi, vol) in sortedVolumes.enumerated() {
            let volID = "vol\(vi)"
            let volFile = "\(volID).xhtml"
            let volXhtml = wrapXHTML(title: vol.title, body: "<h1 class=\"vol-title\">\(escape(vol.title))</h1>")
            var secs: [SecEntry] = []
            for (si, sec) in vol.sections.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
                let secID = "sec\(vi)_\(si)"
                let secFile = "\(secID).xhtml"
                let body = "<h1 class=\"sec-title\">\(escape(sec.title))</h1>\n" + parseToXHTML(sec.content)
                secs.append(SecEntry(id: secID, file: secFile, title: sec.title, xhtml: wrapXHTML(title: sec.title, body: body)))
            }
            volumes.append(VolEntry(id: volID, file: volFile, title: vol.title, xhtml: volXhtml, sections: secs))
        }

        // mimetype（必須精確、stored、第一）
        let mimetype = "application/epub+zip"

        // container.xml
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

        // style.css
        let css = """
        body { font-family: -apple-system, "PingFang TC", "Heiti TC", sans-serif; margin: 2em; line-height: 1.7; color: #222; }
        h1 { font-size: 1.8em; margin: 1.2em 0 0.6em; }
        h2 { font-size: 1.3em; font-weight: bold; margin: 1.4em 0 0.5em; }
        p  { margin: 0.4em 0; }
        .cover { text-align: center; margin-top: 28%; }
        .cover .title { font-size: 2.6em; font-weight: bold; }
        .cover .author { font-size: 1.2em; margin-top: 1em; color: #555; }
        .vol-title { text-align: center; margin-top: 30%; font-size: 2em; }
        .sec-title { page-break-before: always; }
        """

        // cover.xhtml（純文字排版封面）
        let cover = wrapXHTML(title: book.title, body:
            "<div class=\"cover\"><div class=\"title\">\(escape(book.title))</div><div class=\"author\">\(escape(book.author))</div></div>")

        // nav.xhtml（EPUB3 導覽文件）
        var navOL = "<li><a href=\"cover.xhtml\">封面</a></li>\n"
        for v in volumes {
            navOL += "<li><a href=\"\(v.file)\">\(escape(v.title))</a>"
            if !v.sections.isEmpty {
                navOL += "\n<ol>\n"
                for s in v.sections { navOL += "<li><a href=\"\(s.file)\">\(escape(s.title))</a></li>\n" }
                navOL += "</ol>\n"
            }
            navOL += "</li>\n"
        }
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>目錄</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body><nav epub:type="toc" id="toc"><h1>目錄</h1>\n<ol>\n\(navOL)</ol></nav></body>
        </html>
        """

        // content.opf
        let modified = iso8601UTC(Date())
        var manifest = """
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="css" href="style.css" media-type="text/css"/>
            <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
        """
        var spine = """
            <itemref idref="cover"/>
            <itemref idref="nav"/>
        """
        for v in volumes {
            manifest += "\n    <item id=\"\(v.id)\" href=\"\(v.file)\" media-type=\"application/xhtml+xml\"/>"
            spine += "\n    <itemref idref=\"\(v.id)\"/>"
            for s in v.sections {
                manifest += "\n    <item id=\"\(s.id)\" href=\"\(s.file)\" media-type=\"application/xhtml+xml\"/>"
                spine += "\n    <itemref idref=\"\(s.id)\"/>"
            }
        }
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="BookId">urn:uuid:\(book.id.uuidString)</dc:identifier>
            <dc:title>\(escape(book.title))</dc:title>
            <dc:language>zh</dc:language>
            <dc:creator>\(escape(book.author))</dc:creator>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
        \(manifest)
          </manifest>
          <spine>
        \(spine)
          </spine>
        </package>
        """

        // 組 zip：mimetype 必須第一個
        var zip = ZipBuilder()
        zip.addEntry("mimetype", Data(mimetype.utf8))
        zip.addEntry("META-INF/container.xml", Data(container.utf8))
        zip.addEntry("OEBPS/content.opf", Data(opf.utf8))
        zip.addEntry("OEBPS/nav.xhtml", Data(nav.utf8))
        zip.addEntry("OEBPS/style.css", Data(css.utf8))
        zip.addEntry("OEBPS/cover.xhtml", Data(cover.utf8))
        for v in volumes {
            zip.addEntry("OEBPS/\(v.file)", Data(v.xhtml.utf8))
            for s in v.sections {
                zip.addEntry("OEBPS/\(s.file)", Data(s.xhtml.utf8))
            }
        }
        return zip.finalize()
    }

    // MARK: - AttributedString → XHTML 段落（幕標題→<h2>，內文→<p>，PRD 10.3）
    private static func parseToXHTML(_ attr: AttributedString) -> String {
        let ns = NSAttributedString(attr)
        let full = ns.string
        var html = ""
        var offset = 0
        let paragraphs = full.components(separatedBy: "\n")
        for para in paragraphs {
            let len = (para as NSString).length
            let range = NSRange(location: offset, length: len)
            var heading = false
            if range.length > 0,
               let f = ns.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                heading = (f.pointSize == 18 && f.fontDescriptor.symbolicTraits.contains(.bold))
            }
            if para.isEmpty {
                html += "<p><br/></p>\n"
            } else if heading {
                html += "<h2>\(escape(para))</h2>\n"
            } else {
                html += "<p>\(escape(para))</p>\n"
            }
            offset += len + 1   // +1 跳過 \n 分隔符
        }
        return html
    }

    private static func wrapXHTML(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>\(escape(title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func sanitize(_ s: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = s.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名" : cleaned
    }

    private static func iso8601UTC(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    // MARK: - 寫 Data 到固定 Downloads 位置（不碰存檔對話框）
    @MainActor
    private static func writeData(_ data: Data, fileName: String) {
        let targetDir = URL(fileURLWithPath: "/Users/hsuchengyu/Downloads", isDirectory: true)
        let url = targetDir.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: targetDir.path)
            print("✅ 已匯出 EPUB 到：\(url.path)")
        } catch {
            print("❌ 無法匯出 EPUB 到 /Users/hsuchengyu/Downloads：\(error)")
        }
    }
}

// MARK: - stored-only zip writer（mimetype 第一個、全部 stored、無 extra field）
private struct ZipBuilder {
    private var data = Data()
    private var central = Data()
    private var entries = 0

    mutating func addEntry(_ name: String, _ fileData: Data) {
        let nameData = Data(name.utf8)
        let crc = Self.crc32(fileData)
        let size = UInt32(fileData.count)
        let offset = UInt32(data.count)

        // local file header
        data.appendLE32(0x04034b50)
        data.appendLE16(20)              // version needed
        data.appendLE16(0)               // flags
        data.appendLE16(0)               // method = stored
        data.appendLE16(0)               // mod time
        data.appendLE16(0x0021)          // mod date (1980-01-01)
        data.appendLE32(crc)
        data.appendLE32(size)            // compressed size
        data.appendLE32(size)            // uncompressed size
        data.appendLE16(UInt16(nameData.count))
        data.appendLE16(0)               // extra field length = 0（mimetype 硬性要求）
        data.append(nameData)
        data.append(fileData)

        // central directory header
        central.appendLE32(0x02014b50)
        central.appendLE16(20)           // version made by
        central.appendLE16(20)           // version needed
        central.appendLE16(0)            // flags
        central.appendLE16(0)            // method = stored
        central.appendLE16(0)            // mod time
        central.appendLE16(0x0021)       // mod date
        central.appendLE32(crc)
        central.appendLE32(size)
        central.appendLE32(size)
        central.appendLE16(UInt16(nameData.count))
        central.appendLE16(0)            // extra
        central.appendLE16(0)            // comment
        central.appendLE16(0)            // disk start
        central.appendLE16(0)            // internal attr
        central.appendLE32(0)            // external attr
        central.appendLE32(offset)       // local header offset
        central.append(nameData)

        entries += 1
    }

    mutating func finalize() -> Data {
        let cdOffset = UInt32(data.count)
        data.append(central)
        let cdSize = UInt32(central.count)
        data.appendLE32(0x06054b50)      // EOCD
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE16(UInt16(entries))
        data.appendLE16(UInt16(entries))
        data.appendLE32(cdSize)
        data.appendLE32(cdOffset)
        data.appendLE16(0)
        return data
    }

    // CRC32（標準 polynomial 0xEDB88320，與 zlib 同款）
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) { var le = v.littleEndian; append(Data(bytes: &le, count: 2)) }
    mutating func appendLE32(_ v: UInt32) { var le = v.littleEndian; append(Data(bytes: &le, count: 4)) }
}
