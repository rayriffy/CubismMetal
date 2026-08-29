import Foundation
import Metal
import simd

extension MetalRenderer {
    struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>

        init(position: SIMD2<Float>, uv: SIMD2<Float>) {
            self.position = position
            self.uv = uv
        }
    }

    struct Uniforms {
        var transform: simd_float4x4
        var opacity: Float
        var padding = SIMD3<Float>(repeating: 0)
    }

    struct MaskUniforms {
        var inverted: Float
        var padding = SIMD3<Float>(repeating: 0)
    }

    final class FrameResources {
        let availability = DispatchSemaphore(value: 1)
        var geometryBuffers: [String: GeometryBuffers] = [:]
        var maskTextures: [MaskKey: MTLTexture] = [:]
    }

    struct GeometryBuffers {
        let vertexBuffer: MTLBuffer
        let indexBuffer: MTLBuffer
        let vertexCapacity: Int
        let indexCapacity: Int

        static func make(device: MTLDevice, vertexByteCount: Int, indexByteCount: Int) -> Self {
            let vertexCapacity = max(vertexByteCount, MemoryLayout<Vertex>.stride)
            let indexCapacity = max(indexByteCount, MemoryLayout<UInt16>.stride)
            guard let vertexBuffer = device.makeBuffer(length: vertexCapacity, options: .storageModeShared),
                  let indexBuffer = device.makeBuffer(length: indexCapacity, options: .storageModeShared)
            else {
                fatalError("Metal buffer allocation failed")
            }
            return Self(
                vertexBuffer: vertexBuffer,
                indexBuffer: indexBuffer,
                vertexCapacity: vertexCapacity,
                indexCapacity: indexCapacity
            )
        }
    }

    struct MaskKey: Hashable {
        let identifiers: [String]

        init(identifiers: [String]) {
            self.identifiers = Array(Set(identifiers)).sorted()
        }
    }
}
