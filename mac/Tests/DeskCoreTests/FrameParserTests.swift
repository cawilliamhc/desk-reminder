import Testing
@testable import DeskCore

private func bytes(_ hex: String) -> [UInt8] {
    stride(from: 0, to: hex.count, by: 2).map {
        let i = hex.index(hex.startIndex, offsetBy: $0)
        return UInt8(hex[i...hex.index(i, offsetBy: 1)], radix: 16)!
    }
}

/// Shaped like the real captures: 30.5" and 44.5".
private let h305 = bytes("F2F201030131073D7E")
private let h445 = bytes("F2F2010301BD07C97E")

private func heights(_ frames: [DeskFrame]) -> [Double?] { frames.map(\.height) }

@Test func singleFrame() {
    var p = FrameParser()
    #expect(heights(p.feed(h305)) == [30.5])
}

@Test func frameSplitAcrossReads() {
    var p = FrameParser()
    #expect(p.feed(Array(h305[0..<1])).isEmpty)
    #expect(p.feed(Array(h305[1..<5])).isEmpty)
    #expect(heights(p.feed(Array(h305[5...]))) == [30.5])
}

@Test func backToBackWithNoise() {
    var p = FrameParser()
    #expect(heights(p.feed([0x00, 0x7E] + h305 + [0xF2] + h445)) == [30.5, 44.5])
}

@Test func badChecksumDroppedAndParserResyncs() {
    var bad = h305
    bad[bad.count - 2] ^= 0xFF
    var p = FrameParser()
    #expect(heights(p.feed(bad + h445)) == [44.5])
}

@Test func nonHeightFrameHasNoHeight() {
    var p = FrameParser()
    let frames = p.feed(bytes("F2F20E0101107E"))
    #expect(frames.count == 1)
    #expect(frames[0].height == nil)
}
