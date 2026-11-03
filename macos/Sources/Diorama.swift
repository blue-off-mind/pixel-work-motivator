// 悬浮窗左边那间 24×24 的像素小办公室：窗外天色跟着真实时间走，
// 打工人在笔记本后面敲键盘；金币飞进左下角的存钱罐，罐子随今日进度装满。
import AppKit

enum Pose {
    case typing, sleeping, fishing, cheering, absent
}

struct DioramaInput {
    var pose: Pose
    var hour: Double // 当地时间（小时，带小数），决定窗外天色
    var jarLevel: Double // 0…1
    var t: Double // 动画时间（秒）
    var coins: [(x: Double, y: Double, age: Double)] = [] // 飞行中的金币（场景坐标，中心点）
    var zzz: [(x: Double, y: Double)] = []
    var sparkle = false // 金币刚落进罐子
}

enum Diorama {
    static let size = 24

    private static let pal: [Character: UInt32] = [
        "k": 0x1B1726, "h": 0x2E2438, "H": 0x4B3C5C, "s": 0xF2C79E, "b": 0xF29A8C,
        "m": 0xA0503C, "M": 0x6E2A2A, "L": 0xD4D1E3, "l": 0xA29EBB, "y": 0xFFC83D,
        "o": 0xE08A1E, "Y": 0xFFF0B3, "N": 0x7A4A12, "n": 0x8F8AB3, "g": 0xA8DCEF,
        "c": 0x2B2A3F, "C": 0x3D3B57, "f": 0x73EFF7, "w": 0xE8E2F2,
    ]

    // MARK: 像素画

    private static let head = [
        "..kkkkkk..",
        ".khhhhhhk.",
        "khhhHHhhhk",
        "khhhhhhhhk",
        "khsshhsshk",
        "kssssssssk",
        "kssessessk",
        "kbssssssbk",
        ".kssmmssk.",
        "..kkkkkk..",
    ]

    private static func head(blink: Bool = false, happy: Bool = false, cheer: Bool = false) -> [String] {
        var rows = head
        if happy {
            rows[5] = "kssksskssk"
            rows[6] = "kskskksksk"
        } else if blink {
            rows[6] = "kssssssssk"
        }
        if cheer { rows[8] = ".ksMMMMsk." }
        return rows
    }

    private static let sleepyHead = [
        "..kkkkkk..",
        ".khhhhhhk.",
        "khhhHHhhhk",
        "khhhhhhhhk",
        "khhhhhhhhk",
    ]

    private static let lidOpen = [
        "kkkkkkkk",
        "kLLLLLlk",
        "kLLyyLlk",
        "kLLooLlk",
        "kLLLLLlk",
        "kkkkkkkk",
    ]

    private static let lidClosed = [
        "kLLLLLLk",
        "kkkkkkkk",
    ]

    private static let jar = [
        ".kkkk.",
        ".knnk.",
        "g....g",
        "g....g",
        "g....g",
        "g....g",
        "g....g",
        "gggggg",
    ]

    private static let phone = ["kkk", "kfk", "kfk", "kkk"]
    private static let fish = [".ff.f", "fkfff", ".ff.f"]
    private static let zee = ["www", "..w", ".w.", "www"]
    private static let coinFrames = [
        [".NNN.", "NYyyN", "NyyoN", "NyooN", ".NNN."],
        ["..N..", ".NYN.", ".NyN.", ".NoN.", "..N.."],
        ["..N..", "..y..", "..y..", "..o..", "..N.."],
        ["..N..", ".NYN.", ".NyN.", ".NoN.", "..N.."],
    ]

    // MARK: 渲染

    static func render(_ input: DioramaInput) -> CGImage {
        var bmp = PixelBitmap(width: size, height: size)
        room(&bmp, hour: input.hour, t: input.t)
        jar(&bmp, level: input.jarLevel, sparkle: input.sparkle)
        character(&bmp, input)
        for z in input.zzz { bmp.blit(zee, Int(z.x.rounded()), Int(z.y.rounded()), pal) }
        for c in input.coins {
            let frame = coinFrames[Int(c.age * 14) % coinFrames.count]
            bmp.blit(frame, Int(c.x.rounded()) - 2, Int(c.y.rounded()) - 2, pal)
        }
        return bmp.image()
    }

    private static func room(_ bmp: inout PixelBitmap, hour: Double, t: Double) {
        bmp.rect(0, 0, 24, 12, 0x3D3A5C) // 墙
        bmp.rect(0, 12, 24, 1, 0x4A4565) // 护墙线
        bmp.rect(0, 13, 24, 7, 0x34314F)
        sky(&bmp, hour: hour, t: t)
        let frame: UInt32 = 0x8F8AB3
        bmp.rect(1, 1, 8, 1, frame)
        bmp.rect(1, 7, 8, 1, frame)
        bmp.rect(1, 1, 1, 7, frame)
        bmp.rect(8, 1, 1, 7, frame)
        bmp.rect(0, 8, 10, 1, 0xA9A4C8) // 窗台
        bmp.rect(0, 20, 24, 1, 0xD08D55) // 桌面
        bmp.rect(0, 21, 24, 1, 0xB0703F)
        bmp.rect(0, 22, 24, 2, 0x6B3F25)
    }

    /// 窗外：x 2…7，y 2…6。按钟点换配色，白天有太阳和云，夜里有月亮和星星。
    private static func sky(_ bmp: inout PixelBitmap, hour h: Double, t: Double) {
        let bands: [UInt32]
        let night = h < 5.5 || h >= 19.5
        switch h {
        case ..<5.5: bands = [0x0E1030, 0x151A42, 0x1C2350]
        case ..<7: bands = [0x4A5AA8, 0xE08A8A, 0xF6C07A]
        case ..<16: bands = [0x3D9BE0, 0x6CB8EC, 0xA8DCF5]
        case ..<18: bands = [0x5A6AB8, 0xE0907A, 0xF6B26B]
        case ..<19.5: bands = [0x2A2660, 0x5A3A7A, 0xA0527A]
        default: bands = [0x0E1030, 0x151A42, 0x1C2350]
        }
        bmp.rect(2, 2, 6, 1, bands[0])
        bmp.rect(2, 3, 6, 2, bands[1])
        bmp.rect(2, 5, 6, 2, bands[2])
        if night {
            let stars = [(3, 2), (7, 3), (2, 5), (6, 6)]
            for (i, s) in stars.enumerated() where (Int(t * 1.2) + i) % 4 != 0 {
                bmp.set(s.0, s.1, 0xFFF6D5)
            }
            bmp.set(5, 3, 0xF4F0D0) // 月牙
            bmp.set(5, 4, 0xF4F0D0)
            bmp.set(6, 4, 0xF4F0D0)
        } else if h >= 7 && h < 18 {
            let sx = 2 + Int(((h - 7) / 11 * 4).rounded())
            bmp.rect(min(6, sx), 3, 2, 2, 0xFFE27A)
            let cx = 1 + Int(t / 2.5) % 9 // 云从左飘到右
            for (dx, dy) in [(0, 5), (1, 5), (2, 5), (1, 4)] {
                let x = cx + dx
                if x >= 2 && x <= 7 { bmp.set(x, dy, 0xF4F8FF) }
            }
        }
    }

    private static func jar(_ bmp: inout PixelBitmap, level: Double, sparkle: Bool) {
        bmp.rect(2, 14, 4, 5, 0x2D3A5C) // 玻璃里面
        let rows = Int((min(1, max(0, level)) * 5).rounded())
        for r in 0..<rows {
            let y = 18 - r
            for x in 2...5 { bmp.set(x, y, (x + y) % 2 == 0 ? 0xFFC83D : 0xE08A1E) }
            if r == rows - 1 { bmp.set(3, y, 0xFFF0B3) }
        }
        if rows < 4 { bmp.set(2, 14, 0xE6F7FD) }
        if rows < 3 { bmp.set(2, 15, 0xE6F7FD) }
        bmp.blit(jar, 1, 12, pal)
        if sparkle {
            for (x, y) in [(3, 10), (4, 10), (3, 9), (4, 11), (2, 10), (5, 10)] { bmp.set(x, y, 0xFFF0B3) }
        }
    }

    /// 办公椅靠背：x 11…22，y 9…19，顶上两级圆角。
    private static func chairBack(_ bmp: inout PixelBitmap) {
        let k = pal["k"]!, c = pal["c"]!, hi = pal["C"]!
        bmp.rect(13, 9, 8, 1, k)
        bmp.set(12, 10, k)
        bmp.rect(13, 10, 8, 1, c)
        bmp.set(21, 10, k)
        for y in 11...18 {
            bmp.set(11, y, k)
            bmp.set(12, y, hi)
            bmp.rect(13, y, 9, 1, c)
            bmp.set(22, y, k)
        }
        bmp.rect(11, 19, 12, 1, k)
    }

    private static func plaid(_ x: Int, _ y: Int) -> UInt32 {
        let vx = x % 3 == 0, hy = y % 3 == 0
        if vx && hy { return 0xE9806A }
        if vx || hy { return 0x8A2C36 }
        return 0xC8463F
    }

    /// 格子衫躯干：x 12…21，y 13…19。
    private static func torso(_ bmp: inout PixelBitmap) {
        bmp.rect(13, 13, 8, 1, pal["k"]!)
        for y in 14...19 { for x in 12...21 { bmp.set(x, y, plaid(x, y)) } }
        bmp.set(12, 14, pal["k"]!)
        bmp.set(21, 14, pal["k"]!)
    }

    /// 两只胳膊：左 x 11…12，右 x 21…22；down 是往下沉的像素数（敲键盘时一上一下）。
    private static func arms(_ bmp: inout PixelBitmap, leftDown: Int, rightDown: Int) {
        let k = pal["k"]!
        for (x0, down, outer) in [(11, leftDown, 11), (21, rightDown, 22)] {
            let top = 14 + down
            bmp.rect(x0, top - 1, 2, 1, k)
            for y in top...19 {
                bmp.set(outer, y, k)
                bmp.set(outer == 11 ? 12 : 21, y, plaid(x0, y))
            }
        }
    }

    /// 欢呼：两只胳膊举过头顶。左 x 10…11，右 x 22…23。
    private static func raisedArms(_ bmp: inout PixelBitmap) {
        let k = pal["k"]!, s = pal["s"]!
        bmp.rect(10, 5, 2, 2, s)
        bmp.rect(22, 5, 2, 2, s)
        for y in 7...14 {
            bmp.set(10, y, k)
            bmp.set(11, y, plaid(11, y))
            bmp.set(22, y, plaid(22, y))
            bmp.set(23, y, k)
        }
    }

    private static func character(_ bmp: inout PixelBitmap, _ input: DioramaInput) {
        let t = input.t
        switch input.pose {
        case .absent:
            chairBack(&bmp)
            bmp.blit(lidClosed, 13, 18, pal)

        case .typing:
            chairBack(&bmp)
            torso(&bmp)
            let beat = Int(t * 5) % 2
            arms(&bmp, leftDown: beat, rightDown: 1 - beat)
            let blink = t.truncatingRemainder(dividingBy: 3.4) < 0.15
            let nod = t.truncatingRemainder(dividingBy: 2.6) < 0.3 ? 1 : 0
            bmp.blit(head(blink: blink), 12, 3 + nod, pal)
            bmp.blit(lidOpen, 13, 14, pal)

        case .fishing:
            chairBack(&bmp)
            torso(&bmp)
            arms(&bmp, leftDown: 0, rightDown: 0)
            bmp.blit(head(happy: true), 12, 3, pal)
            bmp.blit(lidOpen, 13, 14, pal)
            bmp.blit(phone, 15, 11, pal)
            bmp.set(14, 13, pal["s"]!)
            bmp.set(18, 13, pal["s"]!)
            bmp.blit(fish, 18, Int(t * 2) % 2, pal)

        case .cheering:
            chairBack(&bmp)
            torso(&bmp)
            raisedArms(&bmp)
            let hop = Int(t * 4) % 2
            bmp.blit(head(happy: true, cheer: true), 12, 3 - hop, pal)
            bmp.blit(lidOpen, 13, 14, pal)

        case .sleeping:
            chairBack(&bmp)
            for y in 16...19 { for x in 10...23 { bmp.set(x, y, plaid(x, y)) } } // 趴在胳膊上
            bmp.rect(10, 15, 14, 1, pal["k"]!)
            bmp.rect(10, 16, 1, 4, pal["k"]!)
            bmp.rect(23, 16, 1, 4, pal["k"]!)
            let breathe = t.truncatingRemainder(dividingBy: 2) < 1 ? 0 : 1
            bmp.blit(sleepyHead, 12, 11 + breathe, pal)
        }
    }
}
