//
//  MetalRenderPipeline.swift
//  SwiftTerm
//
//  Metal 렌더링 파이프라인 관리
//

#if os(macOS)
import Metal
import MetalKit

/// Metal 렌더링 파이프라인
/// 배경, 글리프, 장식을 순차적으로 렌더링
public class MetalRenderPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// 파이프라인 상태
    private var backgroundPipelineState: MTLRenderPipelineState!
    private var glyphPipelineState: MTLRenderPipelineState!
    private var decorationPipelineState: MTLRenderPipelineState!
    private var cursorPipelineState: MTLRenderPipelineState!
    private var selectionPipelineState: MTLRenderPipelineState!

    public init(device: MTLDevice, metalLibrary: MTLLibrary? = nil) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw MetalRendererError.failedToCreateCommandQueue
        }
        self.commandQueue = queue

        try createPipelineStates(library: metalLibrary)
    }

    private func createPipelineStates(library: MTLLibrary?) throws {
        // 셰이더 라이브러리 로드
        let lib: MTLLibrary
        if let providedLibrary = library {
            lib = providedLibrary
        } else if let defaultLib = device.makeDefaultLibrary() {
            lib = defaultLib
        } else {
            // 번들에서 셰이더 파일 로드 시도
            lib = try loadShaderLibrary()
        }

        // 배경 파이프라인
        let bgDescriptor = MTLRenderPipelineDescriptor()
        bgDescriptor.label = "Background Pipeline"
        bgDescriptor.vertexFunction = lib.makeFunction(name: "backgroundVertexShader")
        bgDescriptor.fragmentFunction = lib.makeFunction(name: "backgroundFragmentShader")
        bgDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundPipelineState = try device.makeRenderPipelineState(descriptor: bgDescriptor)

        // 글리프 파이프라인
        let glyphDescriptor = MTLRenderPipelineDescriptor()
        glyphDescriptor.label = "Glyph Pipeline"
        glyphDescriptor.vertexFunction = lib.makeFunction(name: "glyphVertexShader")
        glyphDescriptor.fragmentFunction = lib.makeFunction(name: "glyphFragmentShader")
        glyphDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // 알파 블렌딩 활성화
        glyphDescriptor.colorAttachments[0].isBlendingEnabled = true
        glyphDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        glyphDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        glyphPipelineState = try device.makeRenderPipelineState(descriptor: glyphDescriptor)

        // 장식 파이프라인 (언더라인, 취소선)
        let decoDescriptor = MTLRenderPipelineDescriptor()
        decoDescriptor.label = "Decoration Pipeline"
        decoDescriptor.vertexFunction = lib.makeFunction(name: "decorationVertexShader")
        decoDescriptor.fragmentFunction = lib.makeFunction(name: "decorationFragmentShader")
        decoDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        decorationPipelineState = try device.makeRenderPipelineState(descriptor: decoDescriptor)

        // 커서 파이프라인
        let cursorDescriptor = MTLRenderPipelineDescriptor()
        cursorDescriptor.label = "Cursor Pipeline"
        cursorDescriptor.vertexFunction = lib.makeFunction(name: "cursorVertexShader")
        cursorDescriptor.fragmentFunction = lib.makeFunction(name: "cursorFragmentShader")
        cursorDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        cursorDescriptor.colorAttachments[0].isBlendingEnabled = true
        cursorDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        cursorDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        cursorPipelineState = try device.makeRenderPipelineState(descriptor: cursorDescriptor)

        // 선택 영역 파이프라인
        let selDescriptor = MTLRenderPipelineDescriptor()
        selDescriptor.label = "Selection Pipeline"
        selDescriptor.vertexFunction = lib.makeFunction(name: "selectionVertexShader")
        selDescriptor.fragmentFunction = lib.makeFunction(name: "selectionFragmentShader")
        selDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        selDescriptor.colorAttachments[0].isBlendingEnabled = true
        selDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        selDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        selectionPipelineState = try device.makeRenderPipelineState(descriptor: selDescriptor)
    }

    private func loadShaderLibrary() throws -> MTLLibrary {
        // 번들에서 .metallib 파일 찾기
        let bundle = Bundle(for: type(of: self))

        if let libraryURL = bundle.url(forResource: "default", withExtension: "metallib") {
            return try device.makeLibrary(URL: libraryURL)
        }

        // .metal 파일에서 컴파일
        if let metalURL = bundle.url(forResource: "TerminalShaders", withExtension: "metal") {
            let source = try String(contentsOf: metalURL, encoding: .utf8)
            return try device.makeLibrary(source: source, options: nil)
        }

        throw MetalRendererError.failedToLoadShaderLibrary
    }

    /// 렌더링 수행
    public func render(
        to drawable: CAMetalDrawable,
        instanceBuffer: MTLBuffer,
        uniformBuffer: MTLBuffer,
        glyphTexture: MTLTexture,
        instanceCount: Int,
        clearColor: MTLClearColor,
        cursorInfo: CursorRenderInfo?,
        selectionRects: [simd_float4]?
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        commandBuffer.label = "Terminal Render"

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.label = "Terminal Encoder"

        // 1. 배경 렌더링
        if instanceCount > 0 {
            encoder.setRenderPipelineState(backgroundPipelineState)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        }

        // 2. 선택 영역 렌더링 (배경 위, 글리프 아래)
        if let rects = selectionRects, !rects.isEmpty {
            renderSelection(encoder: encoder, rects: rects, uniformBuffer: uniformBuffer)
        }

        // 3. 글리프 렌더링
        if instanceCount > 0 {
            encoder.setRenderPipelineState(glyphPipelineState)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(glyphTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        }

        // 4. 장식 렌더링 (언더라인, 취소선)
        if instanceCount > 0 {
            encoder.setRenderPipelineState(decorationPipelineState)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount)
        }

        // 5. 커서 렌더링
        if let cursor = cursorInfo, cursor.visible {
            renderCursor(encoder: encoder, cursor: cursor, uniformBuffer: uniformBuffer)
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// 선택 영역 렌더링
    private func renderSelection(encoder: MTLRenderCommandEncoder, rects: [simd_float4], uniformBuffer: MTLBuffer) {
        encoder.setRenderPipelineState(selectionPipelineState)

        // 선택 영역 버퍼 생성
        var rectData = rects
        let bufferSize = MemoryLayout<simd_float4>.stride * rects.count
        guard let rectBuffer = device.makeBuffer(bytes: &rectData, length: bufferSize, options: .storageModeShared) else { return }

        // 선택 색상 (반투명 파란색)
        var selectionColor = simd_float4(0.2, 0.4, 0.8, 0.4)

        encoder.setVertexBuffer(rectBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&selectionColor, length: MemoryLayout<simd_float4>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: rects.count)
    }

    /// 커서 렌더링
    private func renderCursor(encoder: MTLRenderCommandEncoder, cursor: CursorRenderInfo, uniformBuffer: MTLBuffer) {
        encoder.setRenderPipelineState(cursorPipelineState)

        var position = cursor.position
        var color = cursor.color
        var style: UInt32 = cursor.style.rawValue

        encoder.setVertexBytes(&position, length: MemoryLayout<simd_float2>.stride, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setVertexBytes(&color, length: MemoryLayout<simd_float4>.stride, index: 2)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.setFragmentBytes(&style, length: MemoryLayout<UInt32>.stride, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    /// 커맨드 큐 접근
    public var queue: MTLCommandQueue {
        commandQueue
    }
}

/// 커서 렌더링 정보
public struct CursorRenderInfo {
    public var position: simd_float2
    public var color: simd_float4
    public var style: MetalCursorStyle
    public var visible: Bool

    public init(position: simd_float2, color: simd_float4, style: MetalCursorStyle, visible: Bool) {
        self.position = position
        self.color = color
        self.style = style
        self.visible = visible
    }
}

/// Metal 렌더링용 커서 스타일
public enum MetalCursorStyle: UInt32 {
    case block = 0
    case underline = 1
    case bar = 2
}

#endif
