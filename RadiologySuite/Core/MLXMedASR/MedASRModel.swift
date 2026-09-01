import Foundation
import MLX
import MLXFast
import MLXNN
import OSLog

// MARK: - BatchNorm (inference)

class BatchNormInference: Module, UnaryLayer {
    let numFeatures: Int
    let eps: Float
    var weight: MLXArray
    var bias: MLXArray
    var runningMean: MLXArray
    var runningVar: MLXArray

    init(numFeatures: Int, eps: Float = 1e-5) {
        self.numFeatures = numFeatures
        self.eps = eps
        self.weight = MLXArray.ones([numFeatures])
        self.bias = MLXArray.zeros([numFeatures])
        self.runningMean = MLXArray.zeros([numFeatures])
        self.runningVar = MLXArray.ones([numFeatures])
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let normalized = (x - runningMean) / MLX.sqrt(runningVar + MLXArray(eps))
        return weight * normalized + bias
    }
}

class LayerNormNoBias: Module, UnaryLayer {
    let weight: MLXArray
    let dims: Int
    let eps: Float

    init(dims: Int, eps: Float = 1e-6) {
        self.dims = dims
        self.eps = eps
        self.weight = MLXArray.ones([dims])
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLXFast.layerNorm(x, weight: weight, bias: nil, eps: eps)
    }
}

class LasrSubsampling: Module {
    @ModuleInfo(key: "dense_0") var dense0: Linear
    @ModuleInfo(key: "conv_0") var conv0: Conv1d
    @ModuleInfo(key: "conv_1") var conv1: Conv1d
    @ModuleInfo(key: "dense_1") var dense1: Linear

    init(_ config: MedASREncoderConfig) {
        let h = config.hiddenSize
        let k = config.subsamplingConvKernelSize
        let s = config.subsamplingConvStride
        let sc = config.subsamplingConvChannels
        _dense0.wrappedValue = Linear(config.numMelBins, h, bias: true)
        _conv0.wrappedValue = Conv1d(inputChannels: h, outputChannels: h, kernelSize: k, stride: s, padding: 0, bias: true)
        _conv1.wrappedValue = Conv1d(inputChannels: h, outputChannels: sc, kernelSize: k, stride: s, padding: 0, bias: true)
        _dense1.wrappedValue = Linear(sc, h, bias: true)
        super.init()
    }

    func callAsFunction(_ inputFeatures: MLXArray) -> MLXArray {
        var h = relu(dense0(inputFeatures))
        h = relu(conv0(h))
        h = relu(conv1(h))
        return dense1(h)
    }
}

class LasrFeedForward: Module {
    @ModuleInfo(key: "linear1") var linear1: Linear
    @ModuleInfo(key: "linear2") var linear2: Linear
    let hiddenAct: String

    init(_ config: MedASREncoderConfig) {
        hiddenAct = config.hiddenAct
        _linear1.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: config.attentionBias)
        _linear2.wrappedValue = Linear(config.intermediateSize, config.hiddenSize, bias: config.attentionBias)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = linear1(x)
        switch hiddenAct {
        case "relu": h = relu(h)
        case "gelu": h = gelu(h)
        default: h = silu(h)
        }
        return linear2(h)
    }
}

class LasrAttention: Module {
    let numHeads: Int
    let numKVHeads: Int
    let numKVGroups: Int
    let headDim: Int
    let scale: Float

    @ModuleInfo(key: "q_proj") var qProj: Linear
    @ModuleInfo(key: "k_proj") var kProj: Linear
    @ModuleInfo(key: "v_proj") var vProj: Linear
    @ModuleInfo(key: "o_proj") var oProj: Linear

    init(_ config: MedASREncoderConfig) {
        numHeads = config.numAttentionHeads
        numKVHeads = config.numKeyValueHeads
        numKVGroups = numHeads / max(numKVHeads, 1)
        headDim = config.headDim
        scale = pow(Float(headDim), -0.5)
        _qProj.wrappedValue = Linear(config.hiddenSize, numHeads * headDim, bias: config.attentionBias)
        _kProj.wrappedValue = Linear(config.hiddenSize, numKVHeads * headDim, bias: config.attentionBias)
        _vProj.wrappedValue = Linear(config.hiddenSize, numKVHeads * headDim, bias: config.attentionBias)
        _oProj.wrappedValue = Linear(numHeads * headDim, config.hiddenSize, bias: config.attentionBias)
        super.init()
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        positionEmbeddings: (cos: MLXArray, sin: MLXArray),
        attentionMask: MLXArray? = nil
    ) -> MLXArray {
        let bsz = hiddenStates.dim(0)
        let qLen = hiddenStates.dim(1)
        var q = qProj(hiddenStates)
        var k = kProj(hiddenStates)
        var v = vProj(hiddenStates)
        q = q.reshaped(bsz, qLen, numHeads, headDim).transposed(0, 2, 1, 3)
        k = k.reshaped(bsz, qLen, numKVHeads, headDim).transposed(0, 2, 1, 3)
        v = v.reshaped(bsz, qLen, numKVHeads, headDim).transposed(0, 2, 1, 3)

        let cos = positionEmbeddings.cos.expandedDimensions(axis: 1)
        let sin = positionEmbeddings.sin.expandedDimensions(axis: 1)
        q = (q * cos) + (rotateHalf(q) * sin)
        k = (k * cos) + (rotateHalf(k) * sin)

        if numKVGroups > 1 {
            k = repeatKV(k, nRep: numKVGroups)
            v = repeatKV(v, nRep: numKVGroups)
        }

        var attnWeights = MLX.matmul(q, k.transposed(0, 1, 3, 2)) * MLXArray(scale)
        if let mask = attentionMask {
            if mask.ndim == 4 {
                attnWeights = attnWeights + mask[0..., 0..., 0..., ..<k.dim(2)]
            } else {
                attnWeights = attnWeights + mask
            }
        }
        let attnProbs = softmax(attnWeights.asType(.float32), axis: -1).asType(attnWeights.dtype)
        var attnOutput = MLX.matmul(attnProbs, v)
        attnOutput = attnOutput.transposed(0, 2, 1, 3).reshaped(bsz, qLen, numHeads * headDim)
        return oProj(attnOutput)
    }

    private func rotateHalf(_ x: MLXArray) -> MLXArray {
        let half = x.dim(-1) / 2
        let x1 = x[0..., 0..., 0..., ..<half]
        let x2 = x[0..., 0..., 0..., half...]
        return MLX.concatenated([-x2, x1], axis: -1)
    }

    private func repeatKV(_ x: MLXArray, nRep: Int) -> MLXArray {
        if nRep == 1 { return x }
        let expanded = x.expandedDimensions(axis: 2)
        let repeatedKV = MLX.repeated(expanded, count: nRep, axis: 2)
        return repeatedKV.reshaped(repeatedKV.dim(0), repeatedKV.dim(1) * nRep, repeatedKV.dim(3), repeatedKV.dim(4))
    }
}

class DepthwiseConv1d: Module {
    var weight: MLXArray
    var bias: MLXArray?
    let groups: Int
    let stride: Int
    let padding: Int

    init(channels: Int, kernelSize: Int, stride: Int = 1, padding: Int = 0, bias: Bool = false) {
        groups = channels
        self.stride = stride
        self.padding = padding
        weight = MLXArray.zeros([channels, kernelSize, 1])
        self.bias = bias ? MLXArray.zeros([channels]) : nil
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var y = conv1d(x, weight, stride: stride, padding: padding, dilation: 1, groups: groups)
        if let b = bias { y = y + b }
        return y
    }
}

class LasrConvModule: Module {
    let kernelSize: Int
    @ModuleInfo(key: "pointwise_conv1") var pointwiseConv1: Conv1d
    @ModuleInfo(key: "depthwise_conv") var depthwiseConv: DepthwiseConv1d
    @ModuleInfo(key: "norm") var norm: BatchNormInference
    @ModuleInfo(key: "pointwise_conv2") var pointwiseConv2: Conv1d

    init(_ config: MedASREncoderConfig) {
        let channels = config.hiddenSize
        kernelSize = config.convKernelSize
        _pointwiseConv1.wrappedValue = Conv1d(
            inputChannels: channels, outputChannels: 2 * channels,
            kernelSize: 1, stride: 1, padding: 0, bias: config.convolutionBias
        )
        _depthwiseConv.wrappedValue = DepthwiseConv1d(
            channels: channels, kernelSize: kernelSize, stride: 1, padding: 0, bias: config.convolutionBias
        )
        _norm.wrappedValue = BatchNormInference(numFeatures: channels, eps: 1e-5)
        _pointwiseConv2.wrappedValue = Conv1d(
            inputChannels: channels, outputChannels: channels,
            kernelSize: 1, stride: 1, padding: 0, bias: config.convolutionBias
        )
        super.init()
    }

    func callAsFunction(_ hiddenStates: MLXArray, attentionMask: MLXArray? = nil) -> MLXArray {
        var h = pointwiseConv1(hiddenStates)
        let half = h.dim(-1) / 2
        let a = h[0..., 0..., ..<half]
        let b = h[0..., 0..., half...]
        h = a * sigmoid(b)
        if let mask = attentionMask {
            let maskedRows = computeMaskedRows(mask, seqLen: h.dim(1)).expandedDimensions(axis: -1)
            h = MLX.where(maskedRows, MLXArray.zeros(like: h), h)
        }
        h = samePad(h)
        h = depthwiseConv(h)
        h = silu(norm(h))
        return pointwiseConv2(h)
    }

    private func samePad(_ x: MLXArray) -> MLXArray {
        let total = kernelSize - 1
        let left = total / 2
        let right = total - left
        return MLX.padded(x, widths: [[0, 0], [left, right], [0, 0]])
    }

    private func computeMaskedRows(_ mask: MLXArray, seqLen: Int) -> MLXArray {
        if mask.ndim == 2 {
            if mask.dtype == .bool { return .!(mask) }
            return mask .== MLXArray(Float(0))
        }
        if mask.ndim == 4 {
            let allMasked = MLX.all(mask .!= MLXArray(Float(0)), axes: [-1])
            if allMasked.dim(1) == 1 { return allMasked.squeezed(axis: 1) }
            return allMasked
        }
        return MLXArray.zeros([mask.dim(0), seqLen], dtype: .bool)
    }
}

class LasrConformerBlock: Module {
    @ModuleInfo(key: "feed_forward1") var feedForward1: LasrFeedForward
    @ModuleInfo(key: "self_attn") var selfAttn: LasrAttention
    @ModuleInfo(key: "conv") var conv: LasrConvModule
    @ModuleInfo(key: "feed_forward2") var feedForward2: LasrFeedForward
    @ModuleInfo(key: "norm_feed_forward1") var normFeedForward1: LayerNormNoBias
    @ModuleInfo(key: "norm_self_att") var normSelfAtt: LayerNormNoBias
    @ModuleInfo(key: "norm_conv") var normConv: LayerNormNoBias
    @ModuleInfo(key: "norm_feed_forward2") var normFeedForward2: LayerNormNoBias
    @ModuleInfo(key: "norm_out") var normOut: LayerNormNoBias
    let ffResidualWeights: (Float, Float)
    let convResidualWeights: (Float, Float)

    init(_ config: MedASREncoderConfig) {
        ffResidualWeights = (config.feedForwardResidualWeights[0], config.feedForwardResidualWeights[1])
        convResidualWeights = (config.convResidualWeights[0], config.convResidualWeights[1])
        _feedForward1.wrappedValue = LasrFeedForward(config)
        _selfAttn.wrappedValue = LasrAttention(config)
        _conv.wrappedValue = LasrConvModule(config)
        _feedForward2.wrappedValue = LasrFeedForward(config)
        let h = config.hiddenSize
        let eps = config.layerNormEps
        _normFeedForward1.wrappedValue = LayerNormNoBias(dims: h, eps: eps)
        _normSelfAtt.wrappedValue = LayerNormNoBias(dims: h, eps: eps)
        _normConv.wrappedValue = LayerNormNoBias(dims: h, eps: eps)
        _normFeedForward2.wrappedValue = LayerNormNoBias(dims: h, eps: eps)
        _normOut.wrappedValue = LayerNormNoBias(dims: h, eps: eps)
        super.init()
    }

    func callAsFunction(
        _ hiddenStates: MLXArray,
        positionEmbeddings: (cos: MLXArray, sin: MLXArray),
        attentionMask: MLXArray? = nil
    ) -> MLXArray {
        var residual = hiddenStates
        var h = feedForward1(normFeedForward1(hiddenStates))
        h = MLXArray(ffResidualWeights.0) * residual + MLXArray(ffResidualWeights.1) * h
        h = h + selfAttn(normSelfAtt(h), positionEmbeddings: positionEmbeddings, attentionMask: attentionMask)
        let convOutput = conv(normConv(h), attentionMask: attentionMask)
        h = MLXArray(convResidualWeights.0) * h + MLXArray(convResidualWeights.1) * convOutput
        residual = h
        h = feedForward2(normFeedForward2(h))
        h = MLXArray(ffResidualWeights.0) * residual + MLXArray(ffResidualWeights.1) * h
        return normOut(h)
    }
}

class LasrEncoder: Module {
    @ModuleInfo var subsampler: LasrSubsampling
    @ModuleInfo var layers: [LasrConformerBlock]
    @ModuleInfo(key: "out_norm") var outNorm: LayerNormNoBias
    let subsamplingKernel: Int
    let subsamplingStride: Int
    let ropeTheta: Float
    let headDim: Int

    init(_ config: MedASREncoderConfig) {
        subsamplingKernel = config.subsamplingConvKernelSize
        subsamplingStride = config.subsamplingConvStride
        ropeTheta = config.ropeTheta
        headDim = config.headDim
        _subsampler.wrappedValue = LasrSubsampling(config)
        _layers.wrappedValue = (0..<config.numHiddenLayers).map { _ in LasrConformerBlock(config) }
        _outNorm.wrappedValue = LayerNormNoBias(dims: config.hiddenSize, eps: config.layerNormEps)
        super.init()
    }

    func callAsFunction(_ inputFeatures: MLXArray, attentionMask: MLXArray? = nil) -> MLXArray {
        var hiddenStates = subsampler(inputFeatures)
        let seqLen = hiddenStates.dim(1)
        let positionIds = MLXArray(Array(stride(from: Float(0), to: Float(seqLen), by: 1)))
            .expandedDimensions(axis: 0)
        let rope = computeRoPE(positionIds: positionIds, dtype: hiddenStates.dtype)
        var layerAttentionMask: MLXArray?
        if let mask = attentionMask {
            layerAttentionMask = createBidirectionalMask(getOutputAttentionMask(mask, targetLength: seqLen))
        }
        for layer in layers {
            hiddenStates = layer(hiddenStates, positionEmbeddings: rope, attentionMask: layerAttentionMask)
        }
        return outNorm(hiddenStates)
    }

    private func computeRoPE(positionIds: MLXArray, dtype: DType) -> (MLXArray, MLXArray) {
        let invFreqValues = stride(from: 0, to: headDim, by: 2).map { i -> Float in
            1.0 / pow(ropeTheta, Float(i) / Float(headDim))
        }
        let invFreq = MLXArray(invFreqValues)
        let freqs = positionIds.asType(.float32).expandedDimensions(axis: -1) * invFreq
        let emb = MLX.concatenated([freqs, freqs], axis: -1)
        return (MLX.cos(emb).asType(dtype), MLX.sin(emb).asType(dtype))
    }

    private func getSubsamplingOutputLength(_ inputLengths: MLXArray) -> MLXArray {
        var lengths = inputLengths
        for _ in 0..<2 {
            lengths = (lengths - MLXArray(Int32(subsamplingKernel))) / MLXArray(Int32(subsamplingStride)) + 1
        }
        return lengths
    }

    private func getOutputAttentionMask(_ mask: MLXArray, targetLength: Int) -> MLXArray {
        let outputLengths = getSubsamplingOutputLength(mask.sum(axis: -1))
        let positions = MLXArray(Array(0..<Int32(targetLength))).expandedDimensions(axis: 0)
        return positions .< outputLengths.expandedDimensions(axis: -1)
    }

    private func createBidirectionalMask(_ mask: MLXArray) -> MLXArray {
        let keyMask = mask.expandedDimensions(axes: [1, 2])
        let queryMask = mask.expandedDimensions(axes: [1, 3])
        let valid = MLX.logicalAnd(keyMask, queryMask)
        let zeros = MLXArray.zeros(like: valid).asType(.float32)
        let neg = MLXArray.full(valid.shape, values: MLXArray(Float(-1e9)))
        return MLX.where(valid, zeros, neg)
    }
}

class LasrForCTC: Module {
    let config: MedASRConfig
    @ModuleInfo var encoder: LasrEncoder
    @ModuleInfo(key: "ctc_head") var ctcHead: Conv1d

    init(_ config: MedASRConfig) {
        self.config = config
        _encoder.wrappedValue = LasrEncoder(config.encoderConfig)
        _ctcHead.wrappedValue = Conv1d(
            inputChannels: config.encoderConfig.hiddenSize,
            outputChannels: config.vocabSize,
            kernelSize: 1
        )
        super.init()
    }

    func callAsFunction(_ inputFeatures: MLXArray, attentionMask: MLXArray? = nil) -> MLXArray {
        ctcHead(encoder(inputFeatures, attentionMask: attentionMask))
    }

    static func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var result = [String: MLXArray]()
        for (key, value) in weights {
            var newKey = key
            if newKey.hasPrefix("model.") { newKey.removeFirst(6) }
            if newKey.contains(".norm.running_mean") {
                newKey = newKey.replacingOccurrences(of: ".running_mean", with: ".runningMean")
            } else if newKey.contains(".norm.running_var") {
                newKey = newKey.replacingOccurrences(of: ".running_var", with: ".runningVar")
            }
            if newKey.contains("num_batches_tracked") { continue }
            result[newKey] = value
        }
        return result
    }
}

enum MedASRModelLoader {
    private static let log = Logger(subsystem: "RadiologySuite", category: "MedASR")

    static func load(from directory: URL) throws -> LasrForCTC {
        let t0 = CFAbsoluteTimeGetCurrent()
        let configURL = directory.appendingPathComponent("config.json")
        let configData = try Data(contentsOf: configURL)
        let fullConfig = try JSONDecoder().decode(MedASRFullConfig.self, from: configData)
        let model = LasrForCTC(fullConfig.model)

        let candidates = ["model.safetensors", "weights.safetensors", "weights.npz"]
        guard let weightsURL = candidates.map({ directory.appendingPathComponent($0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else {
            throw AppError.modelMissing
        }

        var t = CFAbsoluteTimeGetCurrent()
        let rawWeights = try loadWeightArrays(weightsURL)
        log.info("loadArrays \(weightsURL.lastPathComponent, privacy: .public) \(Int((CFAbsoluteTimeGetCurrent() - t) * 1000)) ms, \(rawWeights.count) tensors")

        let sanitizedWeights = LasrForCTC.sanitize(weights: rawWeights)

        if let qConfig = fullConfig.quantization, qConfig.enabled {
            quantize(model: model) { path, _ in
                if sanitizedWeights["\(path).scales"] != nil {
                    return (qConfig.groupSize, qConfig.bits)
                }
                return nil
            }
        }

        t = CFAbsoluteTimeGetCurrent()
        try model.update(parameters: ModuleParameters.unflattened(sanitizedWeights))
        log.info("update(parameters) \(Int((CFAbsoluteTimeGetCurrent() - t) * 1000)) ms")

        t = CFAbsoluteTimeGetCurrent()
        eval(model)
        log.info("eval(model) \(Int((CFAbsoluteTimeGetCurrent() - t) * 1000)) ms; total load \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms")
        return model
    }

    private static func loadWeightArrays(_ url: URL) throws -> [String: MLXArray] {
        switch url.pathExtension.lowercased() {
        case "safetensors":
            return try MLX.loadArrays(url: url)
        case "npz":
            return try NPZLoader.load(url: url)
        case "npy":
            return ["weight": try MLX.loadArray(url: url)]
        default:
            throw LoadSaveError.unknownExtension(url.pathExtension)
        }
    }
}
