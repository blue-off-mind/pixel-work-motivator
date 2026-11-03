// 8-bit 音效：启动时用方波现场合成 WAV，不带任何音频文件。
import AppKit

@MainActor
enum Sound {
    private static func wav(_ notes: [(freq: Double, dur: Double)], volume: Double = 0.16) -> Data {
        let rate = 22050
        var samples: [Int16] = []
        for note in notes {
            let n = Int(Double(rate) * note.dur)
            for i in 0..<n {
                let t = Double(i) / Double(rate)
                let env = 1 - Double(i) / Double(n) // 每个音符线性衰减
                let square: Double = sin(2 * .pi * note.freq * t) >= 0 ? 1 : -1
                samples.append(Int16(square * env * volume * Double(Int16.max)))
            }
        }
        var data = Data()
        func ascii(_ s: String) { data.append(s.data(using: .ascii)!) }
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(36 + samples.count * 2); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        ascii("data"); u32(samples.count * 2)
        for s in samples { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    private static let coinSound = NSSound(data: wav([(987.77, 0.07), (1318.51, 0.3)]))
    private static let fanfareSound = NSSound(data: wav([
        (523.25, 0.09), (659.25, 0.09), (783.99, 0.09), (1046.5, 0.18), (783.99, 0.09), (1046.5, 0.45),
    ]))

    static func coin() {
        coinSound?.stop()
        coinSound?.play()
    }

    static func fanfare() {
        fanfareSound?.stop()
        fanfareSound?.play()
    }
}
