/*
 * Copyright (c) 2021-2022, NVIDIA CORPORATION. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "LayerNormPlugin.h"

// class LayerNormPlugin
__global__ void layerNormKernelV1(float *pInput, float *pOutput, float epsilon)
{
    const int tx = threadIdx.x, index = blockIdx.x * 256 + threadIdx.x;

    __shared__ float temp[128];

    float value0 = pInput[index];
    float value1 = pInput[index + 128];
    temp[tx]     = value0 + value1;
    __syncthreads();

    for (int stride = 64; stride >= 1; stride /= 2)
    {
        if (tx < stride)
        {
            temp[tx] += temp[tx + stride];
        }
        __syncthreads();
    }
    float mean = temp[0] / 256;
    __syncthreads();

    temp[tx] = (value0 - mean) * (value0 - mean) + (value1 - mean) * (value1 - mean);
    __syncthreads();

    for (int stride = 64; stride >= 1; stride /= 2)
    {
        if (tx < stride)
        {
            temp[tx] += temp[tx + stride];
        }
        __syncthreads();
    }
    float var = temp[0] / 256;

    pOutput[index]       = (value0 - mean) * rsqrtf(var + epsilon);
    pOutput[index + 128] = (value1 - mean) * rsqrtf(var + epsilon);
}

namespace nvinfer1
{
// class LayerNormPlugin
LayerNormPlugin::LayerNormPlugin(const std::string &name, float epsilon):
    name_(name)
{
    WHERE_AM_I();
    m_.epsilon = epsilon;
}

LayerNormPlugin::LayerNormPlugin(const std::string &name, const void *buffer, size_t length):
    name_(name)
{
    WHERE_AM_I();
    memcpy(&m_, buffer, sizeof(m_));
}

LayerNormPlugin::~LayerNormPlugin()
{
    WHERE_AM_I();
}

IPluginV2DynamicExt *LayerNormPlugin::clone() const noexcept
{
    WHERE_AM_I();
    auto p = new LayerNormPlugin(name_, &m_, sizeof(m_));
    p->setPluginNamespace(namespace_.c_str());
    return p;
}

int32_t LayerNormPlugin::getNbOutputs() const noexcept
{
    WHERE_AM_I();
    return 1;
}

DataType LayerNormPlugin::getOutputDataType(int32_t index, DataType const *inputTypes, int32_t nbInputs) const noexcept
{
    WHERE_AM_I();
    return DataType::kFLOAT;
}

DimsExprs LayerNormPlugin::getOutputDimensions(int32_t outputIndex, const DimsExprs *inputs, int32_t nbInputs, IExprBuilder &exprBuilder) noexcept
{
    WHERE_AM_I();
    return inputs[0];
}

bool LayerNormPlugin::supportsFormatCombination(int32_t pos, const PluginTensorDesc *inOut, int32_t nbInputs, int32_t nbOutputs) noexcept
{
    WHERE_AM_I();
    switch (pos)
    {
    case 0:
        return inOut[0].type == DataType::kFLOAT && inOut[0].format == TensorFormat::kLINEAR;
    case 1:
        return inOut[1].type == inOut[0].type && inOut[1].format == inOut[0].format;
    default: // should NOT be here!
        return false;
    }
    return false;
}

void LayerNormPlugin::configurePlugin(const DynamicPluginTensorDesc *in, int32_t nbInputs, const DynamicPluginTensorDesc *out, int32_t nbOutputs) noexcept
{
    WHERE_AM_I();
    return;
}

size_t LayerNormPlugin::getWorkspaceSize(const PluginTensorDesc *inputs, int32_t nbInputs, const PluginTensorDesc *outputs, int32_t nbOutputs) const noexcept
{
    WHERE_AM_I();
    return 0;
}

int32_t LayerNormPlugin::enqueue(const PluginTensorDesc *inputDesc, const PluginTensorDesc *outputDesc, const void *const *inputs, void *const *outputs, void *workspace, cudaStream_t stream) noexcept
{
    WHERE_AM_I();
    const int nBlock = inputDesc[0].dims.d[0] * inputDesc[0].dims.d[1]; // 仅用于处理 nEmbedding 为 256 的情况

    layerNormKernelV1<<<nBlock, 128, 0, stream>>>((float *)inputs[0], (float *)outputs[0], m_.epsilon);
    return 0;
}

void LayerNormPlugin::destroy() noexcept
{
    WHERE_AM_I();
    delete this;
    return;
}

int32_t LayerNormPlugin::initialize() noexcept
{
    WHERE_AM_I();
    return 0;
}

void LayerNormPlugin::terminate() noexcept
{
    WHERE_AM_I();
    return;
}

size_t LayerNormPlugin::getSerializationSize() const noexcept
{
    WHERE_AM_I();
    return sizeof(m_);
}

void LayerNormPlugin::serialize(void *buffer) const noexcept
{
    WHERE_AM_I();
    memcpy(buffer, &m_, sizeof(m_));
    return;
}

void LayerNormPlugin::setPluginNamespace(const char *pluginNamespace) noexcept
{
    WHERE_AM_I();
    namespace_ = pluginNamespace;
    return;
}

const char *LayerNormPlugin::getPluginNamespace() const noexcept
{
    WHERE_AM_I();
    return namespace_.c_str();
}

const char *LayerNormPlugin::getPluginType() const noexcept
{
    WHERE_AM_I();
    return PLUGIN_NAME;
}

const char *LayerNormPlugin::getPluginVersion() const noexcept
{
    WHERE_AM_I();
    return PLUGIN_VERSION;
}

void LayerNormPlugin::attachToContext(cudnnContext *contextCudnn, cublasContext *contextCublas, IGpuAllocator *gpuAllocator) noexcept
{
    WHERE_AM_I();
    return;
}

void LayerNormPlugin::detachFromContext() noexcept
{
    WHERE_AM_I();
    return;
}

// class LayerNormPluginV1Creator
PluginFieldCollection    LayerNormPluginV1Creator::fc_ {};
std::vector<PluginField> LayerNormPluginV1Creator::attr_;

LayerNormPluginV1Creator::LayerNormPluginV1Creator()
{
    WHERE_AM_I();
    attr_.clear();
    attr_.emplace_back(PluginField("epsilon", nullptr, PluginFieldType::kFLOAT32, 1));
    fc_.nbFields = attr_.size();
    fc_.fields   = attr_.data();
}

LayerNormPluginV1Creator::~LayerNormPluginV1Creator()
{
    WHERE_AM_I();
}

IPluginV2 *LayerNormPluginV1Creator::createPlugin(const char *name, const PluginFieldCollection *fc) noexcept
{
    WHERE_AM_I();
    float                          epsilon = 1.0e-5f;
    std::map<std::string, float *> parameterMap {{"epsilon", &epsilon}};

    for (int i = 0; i < fc->nbFields; ++i)
    {
        if (parameterMap.find(fc->fields[i].name) != parameterMap.end())
        {
            *parameterMap[fc->fields[i].name] = *reinterpret_cast<const float *>(fc->fields[i].data);
        }
    }
    return new LayerNormPlugin(name, epsilon);
}

IPluginV2 *LayerNormPluginV1Creator::deserializePlugin(const char *name, const void *serialData, size_t serialLength) noexcept
{
    WHERE_AM_I();
    return new LayerNormPlugin(name, serialData, serialLength);
}

void LayerNormPluginV1Creator::setPluginNamespace(const char *pluginNamespace) noexcept
{
    WHERE_AM_I();
    namespace_ = pluginNamespace;
    return;
}

const char *LayerNormPluginV1Creator::getPluginNamespace() const noexcept
{
    WHERE_AM_I();
    return namespace_.c_str();
}

const char *LayerNormPluginV1Creator::getPluginName() const noexcept
{
    WHERE_AM_I();
    return PLUGIN_NAME;
}

const char *LayerNormPluginV1Creator::getPluginVersion() const noexcept
{
    WHERE_AM_I();
    return PLUGIN_VERSION;
}

const PluginFieldCollection *LayerNormPluginV1Creator::getFieldNames() noexcept
{
    WHERE_AM_I();
    return &fc_;
}

REGISTER_TENSORRT_PLUGIN(LayerNormPluginV1Creator);
} // namespace nvinfer1
