import Darwin
import Foundation

/// C layouts deliberately confined to the dynamic Core boundary.
///
/// These declarations mirror the documented C ABI only. No Cubism Framework
/// headers, sources, static libraries, or Editor runtime are linked into this
/// target.
struct CubismCoreABI {
    typealias GetVersion = @convention(c) () -> UInt32
    typealias HasMocConsistency = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Int32
    typealias ReviveMocInPlace = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
    typealias GetSizeofModel = @convention(c) (UnsafeRawPointer?) -> UInt32
    typealias InitializeModelInPlace = @convention(c) (
        UnsafeRawPointer?,
        UnsafeMutableRawPointer?,
        UInt32
    ) -> UnsafeMutableRawPointer?
    typealias UpdateModel = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias ReadCanvasInfo = @convention(c) (
        UnsafeRawPointer?,
        UnsafeMutableRawPointer?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<Float>?
    ) -> Void

    typealias GetCount = @convention(c) (UnsafeRawPointer?) -> Int32
    typealias GetIDs = @convention(c) (
        UnsafeRawPointer?
    ) -> UnsafePointer<UnsafePointer<CChar>?>?
    typealias GetMutableFloats = @convention(c) (
        UnsafeMutableRawPointer?
    ) -> UnsafeMutablePointer<Float>?
    typealias GetFlags = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<UInt8>?
    typealias GetInts = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<Int32>?
    typealias GetFloatValues = @convention(c) (UnsafeRawPointer?) -> UnsafePointer<Float>?
    typealias GetMasks = @convention(c) (
        UnsafeRawPointer?
    ) -> UnsafePointer<UnsafePointer<Int32>?>?
    typealias GetVector2Lists = @convention(c) (
        UnsafeRawPointer?
    ) -> UnsafePointer<UnsafeRawPointer?>?
    typealias GetIndexLists = @convention(c) (
        UnsafeRawPointer?
    ) -> UnsafePointer<UnsafePointer<UInt16>?>?
    typealias ResetDrawableDynamicFlags = @convention(c) (UnsafeMutableRawPointer?) -> Void

    let getVersion: GetVersion
    let hasMocConsistency: HasMocConsistency?
    let reviveMocInPlace: ReviveMocInPlace
    let getSizeofModel: GetSizeofModel
    let initializeModelInPlace: InitializeModelInPlace
    let updateModel: UpdateModel
    let readCanvasInfo: ReadCanvasInfo

    let getParameterCount: GetCount
    let getParameterIDs: GetIDs
    let getParameterValues: GetMutableFloats
    let getPartCount: GetCount
    let getPartIDs: GetIDs
    let getPartOpacities: GetMutableFloats

    let getDrawableCount: GetCount
    let getDrawableIDs: GetIDs
    let getDrawableConstantFlags: GetFlags
    let getDrawableDynamicFlags: GetFlags
    let getDrawableBlendModes: GetInts?
    let getDrawableTextureIndices: GetInts
    let getDrawableRenderOrders: GetInts?
    let getRenderOrders: GetInts?
    let getOffscreenCount: GetCount?
    let getDrawableOpacities: GetFloatValues
    let getDrawableMaskCounts: GetInts
    let getDrawableMasks: GetMasks
    let getDrawableVertexCounts: GetInts
    let getDrawableVertexPositions: GetVector2Lists
    let getDrawableVertexUVs: GetVector2Lists
    let getDrawableIndexCounts: GetInts
    let getDrawableIndices: GetIndexLists
    let resetDrawableDynamicFlags: ResetDrawableDynamicFlags?

    init(handle: UnsafeMutableRawPointer, libraryURL: URL) throws {
        getVersion = try Self.required("csmGetVersion", handle: handle, libraryURL: libraryURL)
        hasMocConsistency = Self.optional("csmHasMocConsistency", handle: handle)
        reviveMocInPlace = try Self.required("csmReviveMocInPlace", handle: handle, libraryURL: libraryURL)
        getSizeofModel = try Self.required("csmGetSizeofModel", handle: handle, libraryURL: libraryURL)
        initializeModelInPlace = try Self.required("csmInitializeModelInPlace", handle: handle, libraryURL: libraryURL)
        updateModel = try Self.required("csmUpdateModel", handle: handle, libraryURL: libraryURL)
        readCanvasInfo = try Self.required("csmReadCanvasInfo", handle: handle, libraryURL: libraryURL)

        getParameterCount = try Self.required("csmGetParameterCount", handle: handle, libraryURL: libraryURL)
        getParameterIDs = try Self.required("csmGetParameterIds", handle: handle, libraryURL: libraryURL)
        getParameterValues = try Self.required("csmGetParameterValues", handle: handle, libraryURL: libraryURL)
        getPartCount = try Self.required("csmGetPartCount", handle: handle, libraryURL: libraryURL)
        getPartIDs = try Self.required("csmGetPartIds", handle: handle, libraryURL: libraryURL)
        getPartOpacities = try Self.required("csmGetPartOpacities", handle: handle, libraryURL: libraryURL)

        getDrawableCount = try Self.required("csmGetDrawableCount", handle: handle, libraryURL: libraryURL)
        getDrawableIDs = try Self.required("csmGetDrawableIds", handle: handle, libraryURL: libraryURL)
        getDrawableConstantFlags = try Self.required("csmGetDrawableConstantFlags", handle: handle, libraryURL: libraryURL)
        getDrawableDynamicFlags = try Self.required("csmGetDrawableDynamicFlags", handle: handle, libraryURL: libraryURL)
        getDrawableBlendModes = Self.optional("csmGetDrawableBlendModes", handle: handle)
        getDrawableTextureIndices = try Self.required("csmGetDrawableTextureIndices", handle: handle, libraryURL: libraryURL)
        getDrawableRenderOrders = Self.optional("csmGetDrawableRenderOrders", handle: handle)
        getRenderOrders = Self.optional("csmGetRenderOrders", handle: handle)
        guard getDrawableRenderOrders != nil || getRenderOrders != nil else {
            throw CubismCoreLibraryError.missingRequiredSymbol("csmGetRenderOrders", libraryURL)
        }
        getOffscreenCount = Self.optional("csmGetOffscreenCount", handle: handle)
        getDrawableOpacities = try Self.required("csmGetDrawableOpacities", handle: handle, libraryURL: libraryURL)
        getDrawableMaskCounts = try Self.required("csmGetDrawableMaskCounts", handle: handle, libraryURL: libraryURL)
        getDrawableMasks = try Self.required("csmGetDrawableMasks", handle: handle, libraryURL: libraryURL)
        getDrawableVertexCounts = try Self.required("csmGetDrawableVertexCounts", handle: handle, libraryURL: libraryURL)
        getDrawableVertexPositions = try Self.required("csmGetDrawableVertexPositions", handle: handle, libraryURL: libraryURL)
        getDrawableVertexUVs = try Self.required("csmGetDrawableVertexUvs", handle: handle, libraryURL: libraryURL)
        getDrawableIndexCounts = try Self.required("csmGetDrawableIndexCounts", handle: handle, libraryURL: libraryURL)
        getDrawableIndices = try Self.required("csmGetDrawableIndices", handle: handle, libraryURL: libraryURL)
        resetDrawableDynamicFlags = Self.optional("csmResetDrawableDynamicFlags", handle: handle)
    }

    private static func required<T>(
        _ symbol: String,
        handle: UnsafeMutableRawPointer,
        libraryURL: URL,
        as _: T.Type = T.self
    ) throws -> T {
        guard let pointer = dlsym(handle, symbol) else {
            throw CubismCoreLibraryError.missingRequiredSymbol(symbol, libraryURL)
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func optional<T>(
        _ symbol: String,
        handle: UnsafeMutableRawPointer,
        as _: T.Type = T.self
    ) -> T? {
        guard let pointer = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
