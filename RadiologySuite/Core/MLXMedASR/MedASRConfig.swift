import Foundation

/// Configuration for MedASR Conformer-CTC (`LasrCtcConfig` / `LasrEncoderConfig`).
struct MedASRConfig: Decodable {
    let vocabSize: Int
    let padTokenId: Int
    let encoderConfig: MedASREncoderConfig

    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case padTokenId = "pad_token_id"
        case encoderConfig = "encoder_config"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vocabSize = try container.decodeIfPresent(Int.self, forKey: .vocabSize) ?? 512
        padTokenId = try container.decodeIfPresent(Int.self, forKey: .padTokenId) ?? 0
        encoderConfig = try container.decode(MedASREncoderConfig.self, forKey: .encoderConfig)
    }
}

struct MedASREncoderConfig: Decodable {
    let hiddenSize: Int
    let numHiddenLayers: Int
    let numAttentionHeads: Int
    let numKeyValueHeads: Int
    let intermediateSize: Int
    let attentionBias: Bool
    let convolutionBias: Bool
    let convKernelSize: Int
    let subsamplingConvKernelSize: Int
    let subsamplingConvStride: Int
    let subsamplingConvChannels: Int
    let numMelBins: Int
    let layerNormEps: Float
    let feedForwardResidualWeights: [Float]
    let convResidualWeights: [Float]
    let batchNormMomentum: Float
    let hiddenAct: String
    let attentionDropout: Float
    let dropout: Float
    let dropoutPositions: Float
    let layerdrop: Float
    let activationDropout: Float
    let maxPositionEmbeddings: Int
    let ropeTheta: Float
    let ropeType: String

    var headDim: Int { hiddenSize / numAttentionHeads }

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case intermediateSize = "intermediate_size"
        case attentionBias = "attention_bias"
        case convolutionBias = "convolution_bias"
        case convKernelSize = "conv_kernel_size"
        case subsamplingConvKernelSize = "subsampling_conv_kernel_size"
        case subsamplingConvStride = "subsampling_conv_stride"
        case subsamplingConvChannels = "subsampling_conv_channels"
        case numMelBins = "num_mel_bins"
        case layerNormEps = "layer_norm_eps"
        case feedForwardResidualWeights = "feed_forward_residual_weights"
        case convResidualWeights = "conv_residual_weights"
        case batchNormMomentum = "batch_norm_momentum"
        case hiddenAct = "hidden_act"
        case attentionDropout = "attention_dropout"
        case dropout
        case dropoutPositions = "dropout_positions"
        case layerdrop
        case activationDropout = "activation_dropout"
        case maxPositionEmbeddings = "max_position_embeddings"
        case ropeParameters = "rope_parameters"
    }

    private struct RopeParameters: Decodable {
        let ropeTheta: Float?
        let ropeType: String?
        enum CodingKeys: String, CodingKey {
            case ropeTheta = "rope_theta"
            case ropeType = "rope_type"
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize = try c.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 512
        numHiddenLayers = try c.decodeIfPresent(Int.self, forKey: .numHiddenLayers) ?? 17
        numAttentionHeads = try c.decodeIfPresent(Int.self, forKey: .numAttentionHeads) ?? 8
        numKeyValueHeads = try c.decodeIfPresent(Int.self, forKey: .numKeyValueHeads) ?? numAttentionHeads
        intermediateSize = try c.decodeIfPresent(Int.self, forKey: .intermediateSize) ?? 2048
        attentionBias = try c.decodeIfPresent(Bool.self, forKey: .attentionBias) ?? false
        convolutionBias = try c.decodeIfPresent(Bool.self, forKey: .convolutionBias) ?? false
        convKernelSize = try c.decodeIfPresent(Int.self, forKey: .convKernelSize) ?? 32
        subsamplingConvKernelSize = try c.decodeIfPresent(Int.self, forKey: .subsamplingConvKernelSize) ?? 5
        subsamplingConvStride = try c.decodeIfPresent(Int.self, forKey: .subsamplingConvStride) ?? 2
        subsamplingConvChannels = try c.decodeIfPresent(Int.self, forKey: .subsamplingConvChannels) ?? 256
        numMelBins = try c.decodeIfPresent(Int.self, forKey: .numMelBins) ?? 128
        layerNormEps = try c.decodeIfPresent(Float.self, forKey: .layerNormEps) ?? 1e-6
        feedForwardResidualWeights = try c.decodeIfPresent([Float].self, forKey: .feedForwardResidualWeights) ?? [1.5, 0.5]
        convResidualWeights = try c.decodeIfPresent([Float].self, forKey: .convResidualWeights) ?? [2.0, 1.0]
        batchNormMomentum = try c.decodeIfPresent(Float.self, forKey: .batchNormMomentum) ?? 0.01
        hiddenAct = try c.decodeIfPresent(String.self, forKey: .hiddenAct) ?? "silu"
        attentionDropout = try c.decodeIfPresent(Float.self, forKey: .attentionDropout) ?? 0.1
        dropout = try c.decodeIfPresent(Float.self, forKey: .dropout) ?? 0.1
        dropoutPositions = try c.decodeIfPresent(Float.self, forKey: .dropoutPositions) ?? 0.0
        layerdrop = try c.decodeIfPresent(Float.self, forKey: .layerdrop) ?? 0.0
        activationDropout = try c.decodeIfPresent(Float.self, forKey: .activationDropout) ?? 0.1
        maxPositionEmbeddings = try c.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 10000
        let rope = try c.decodeIfPresent(RopeParameters.self, forKey: .ropeParameters)
        ropeTheta = rope?.ropeTheta ?? 10000.0
        ropeType = rope?.ropeType ?? "default"
    }
}

struct MedASRQuantizationConfig: Decodable {
    let enabled: Bool
    let bits: Int
    let groupSize: Int
    let mode: String

    enum CodingKeys: String, CodingKey {
        case enabled, bits, mode
        case groupSize = "group_size"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        bits = try c.decodeIfPresent(Int.self, forKey: .bits) ?? 8
        groupSize = try c.decodeIfPresent(Int.self, forKey: .groupSize) ?? 64
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "affine"
    }
}

struct MedASRFullConfig: Decodable {
    let model: MedASRConfig
    let quantization: MedASRQuantizationConfig?

    init(from decoder: Decoder) throws {
        model = try MedASRConfig(from: decoder)
        let container = try decoder.container(keyedBy: QuantizationKey.self)
        quantization = try container.decodeIfPresent(MedASRQuantizationConfig.self, forKey: .quantization)
    }

    private enum QuantizationKey: String, CodingKey {
        case quantization = "_quantization"
    }
}
